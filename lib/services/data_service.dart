import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/operator.dart';
import '../models/conversation.dart';

abstract class IDataService {
  Future<void> initializeAsync();
  Future<List<Operator>> getAuthorizedOperatorsAsync();
  Future<void> saveConversationAsync(ConversationSession session);
  Future<void> addSpentAmountAsync(double amount);
  Future<double> getTotalSpentAsync(DateTime start, DateTime end);
  Future<void> recordOperatorVerificationAsync(int operatorId);
  Future<int> getOperatorVerificationCountAsync(int operatorId, DateTime date);
  String get workingHourStart;
  String get workingHourEnd;
}

class DataService implements IDataService {
  final http.Client _httpClient;
  late Database _db;

  String _workingHourStart = "8";
  String _workingHourEnd = "17";
  late String _dataDir;

  DataService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  @override
  String get workingHourStart => _workingHourStart;

  @override
  String get workingHourEnd => _workingHourEnd;

  @override
  Future<void> initializeAsync() async {
    // Determine target local data dir
    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = join(appDir.path, 'ListeningStation');
    final dir = Directory(_dataDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Open SQLite database
    final dbPath = join(_dataDir, 'listening_station.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE AuthorizedOperators (
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            Name TEXT NOT NULL,
            IdNumber TEXT UNIQUE NOT NULL,
            IsActive INTEGER DEFAULT 1
          )
        ''');

        await db.execute('''
          CREATE TABLE Conversations (
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            OperatorId INTEGER,
            StartTime TEXT,
            MessagesJson TEXT,
            SummaryJson TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE BudgetSpent (
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            Date TEXT NOT NULL,
            Amount REAL NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE OperatorVerifications (
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            OperatorId INTEGER,
            VerificationTime TEXT
          )
        ''');
      },
    );

    // Synchronize operator list from remote server
    const remoteUrl = 'http://data.soncamedia.com/firmware/smartbox/listeningStation/operator_list.json';
    final localPath = join(_dataDir, 'operator_list.json');
    final localFile = File(localPath);

    try {
      // 1. Send HEAD request to check size changes
      final headResponse = await _httpClient.head(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 5));
      int remoteSize = -1;
      if (headResponse.statusCode == 200) {
        remoteSize = int.tryParse(headResponse.headers['content-length'] ?? '') ?? -1;
      }

      bool shouldDownload = true;
      if (await localFile.exists()) {
        final localSize = await localFile.length();
        if (remoteSize != -1 && remoteSize == localSize) {
          shouldDownload = false;
          debugPrint("Same file: operator_list.json");
        }
      }

      if (shouldDownload) {
        debugPrint("Downloading operator_list.json...");
        final getResponse = await _httpClient.get(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 10));
        if (getResponse.statusCode == 200) {
          await localFile.writeAsBytes(getResponse.bodyBytes);
          debugPrint("Updated file: operator_list.json");
        }
      }
    } catch (ex) {
      debugPrint("Error syncing operator_list.json: \$ex");
    }

    // Load configuration & parse operators
    if (await localFile.exists()) {
      try {
        final jsonStr = await localFile.readAsString();
        final Map<String, dynamic> doc = jsonDecode(jsonStr);

        if (doc.containsKey('workingHour_Start')) {
          _workingHourStart = doc['workingHour_Start'].toString();
        }
        if (doc.containsKey('workingHour_End')) {
          _workingHourEnd = doc['workingHour_End'].toString();
        }

        if (doc.containsKey('operatorList')) {
          final List<dynamic> opList = doc['operatorList'];
          await _db.transaction((txn) async {
            for (var op in opList) {
              final String? name = op['name'];
              final String? id = op['id'];
              if (name != null && id != null) {
                await txn.insert(
                  'AuthorizedOperators',
                  {'Name': name, 'IdNumber': id, 'IsActive': 1},
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }
            }
          });
        }
      } catch (ex) {
        debugPrint("Error parsing local operator_list.json: \$ex");
      }
    } else {
      // Fallback seed operators
      await _db.insert(
        'AuthorizedOperators',
        {'Name': 'TRƯƠNG HOÀNG MINH', 'IdNumber': '079089017448', 'IsActive': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await _db.insert(
        'AuthorizedOperators',
        {'Name': 'NGUYỄN TRỌNG TÀI', 'IdNumber': '051094009757', 'IsActive': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  @override
  Future<List<Operator>> getAuthorizedOperatorsAsync() async {
    final List<Map<String, dynamic>> maps = await _db.query('AuthorizedOperators');
    return List.generate(maps.length, (i) {
      return Operator(
        id: maps[i]['Id'] ?? 0,
        name: maps[i]['Name'] ?? '',
        idNumber: maps[i]['IdNumber'] ?? '',
        isActive: (maps[i]['IsActive'] ?? 1) == 1,
      );
    });
  }

  @override
  Future<void> saveConversationAsync(ConversationSession session) async {
    await _db.insert('Conversations', {
      'OperatorId': session.operatorId,
      'StartTime': session.startTime.toIso8601String(),
      'MessagesJson': jsonEncode(session.messages.map((m) => m.toJson()).toList()),
      'SummaryJson': session.summaryJson,
    });
  }

  @override
  Future<void> addSpentAmountAsync(double amount) async {
    await _db.insert('BudgetSpent', {
      'Date': DateTime.now().toIso8601String(),
      'Amount': amount,
    });
  }

  @override
  Future<double> getTotalSpentAsync(DateTime start, DateTime end) async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery(
      'SELECT SUM(Amount) as Total FROM BudgetSpent WHERE Date >= ? AND Date <= ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    if (maps.isEmpty || maps.first['Total'] == null) return 0.0;
    return (maps.first['Total'] as num).toDouble();
  }

  @override
  Future<void> recordOperatorVerificationAsync(int operatorId) async {
    await _db.insert('OperatorVerifications', {
      'OperatorId': operatorId,
      'VerificationTime': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<int> getOperatorVerificationCountAsync(int operatorId, DateTime date) async {
    final String dateStr = "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    final List<Map<String, dynamic>> maps = await _db.rawQuery(
      'SELECT COUNT(*) as Count FROM OperatorVerifications WHERE OperatorId = ? AND VerificationTime LIKE ?',
      [operatorId, '$dateStr%'],
    );
    if (maps.isEmpty) return 0;
    return maps.first['Count'] ?? 0;
  }
}
