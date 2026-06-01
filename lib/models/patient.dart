class Patient {
  final int id;
  final String fullName;
  final int age;
  final double monthlyIncome;
  final int familySize;
  final String? medicalConditionFlags; // e.g. "CHRONIC,DISABILITY"
  final String? notes;

  Patient({
    required this.id,
    required this.fullName,
    required this.age,
    required this.monthlyIncome,
    required this.familySize,
    this.medicalConditionFlags,
    this.notes,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['Id'] ?? json['id'] ?? 0,
      fullName: json['FullName'] ?? json['full_name'] ?? '',
      age: json['Age'] ?? json['age'] ?? 0,
      monthlyIncome: (json['MonthlyIncome'] ?? json['monthly_income'] ?? 0.0) is int
          ? (json['MonthlyIncome'] ?? json['monthly_income'] ?? 0.0).toDouble()
          : (json['MonthlyIncome'] ?? json['monthly_income'] ?? 0.0),
      familySize: json['FamilySize'] ?? json['family_size'] ?? 1,
      medicalConditionFlags: json['MedicalConditionFlags'] ?? json['medical_condition_flags'],
      notes: json['Notes'] ?? json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'FullName': fullName,
      'Age': age,
      'MonthlyIncome': monthlyIncome,
      'FamilySize': familySize,
      'MedicalConditionFlags': medicalConditionFlags,
      'Notes': notes,
    };
  }
}

class RuleResult {
  final bool isEligible;
  final double approvedAmount;
  final String explanation;
  final DateTime computedAt;

  RuleResult({
    required this.isEligible,
    required this.approvedAmount,
    required this.explanation,
    required this.computedAt,
  });

  factory RuleResult.fromJson(Map<String, dynamic> json) {
    return RuleResult(
      isEligible: (json['IsEligible'] ?? json['is_eligible'] ?? false) == true,
      approvedAmount: (json['ApprovedAmount'] ?? json['approved_amount'] ?? 0.0) is int
          ? (json['ApprovedAmount'] ?? json['approved_amount'] ?? 0.0).toDouble()
          : (json['ApprovedAmount'] ?? json['approved_amount'] ?? 0.0),
      explanation: json['Explanation'] ?? json['explanation'] ?? '',
      computedAt: json['ComputedAt'] != null
          ? DateTime.parse(json['ComputedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'IsEligible': isEligible,
      'ApprovedAmount': approvedAmount,
      'Explanation': explanation,
      'ComputedAt': computedAt.toIso8601String(),
    };
  }
}
