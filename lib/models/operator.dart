class Operator {
  final int id;
  final String name;
  final String idNumber;
  final String? authToken;
  final bool isActive;

  Operator({
    required this.id,
    required this.name,
    required this.idNumber,
    this.authToken,
    this.isActive = true,
  });

  factory Operator.fromJson(Map<String, dynamic> json) {
    return Operator(
      id: json['Id'] ?? json['id'] ?? 0,
      name: json['Name'] ?? json['name'] ?? '',
      idNumber: json['IdNumber'] ?? json['id_number'] ?? json['id'] ?? '',
      authToken: json['AuthToken'] ?? json['auth_token'],
      isActive: (json['IsActive'] ?? json['is_active'] ?? 1) == 1 || (json['IsActive'] ?? json['is_active']) == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'Name': name,
      'IdNumber': idNumber,
      'AuthToken': authToken,
      'IsActive': isActive ? 1 : 0,
    };
  }
}
