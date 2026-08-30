class DriverEntry {
  final int? id;
  final String date;
  final String dayType;
  final String vehicleNumber;
  final String startTime;
  final String endTime;
  final String int1Start;
  final String int1End;
  final String int2Start;
  final String int2End;
  final double regularHours;
  final double overtimeHours;
  final double intermitenciaHours;
  final double nightHours;
  final bool hasMealAllowance;
  final String firstMeal;
  final String secondMeal;
  final bool hasCollection;

  DriverEntry({
    this.id,
    required this.date,
    required this.dayType,
    this.vehicleNumber = '',
    this.startTime = '',
    this.endTime = '',
    this.int1Start = '',
    this.int1End = '',
    this.int2Start = '',
    this.int2End = '',
    this.regularHours = 0.0,
    this.overtimeHours = 0.0,
    this.intermitenciaHours = 0.0,
    this.nightHours = 0.0,
    this.hasMealAllowance = true,
    this.firstMeal = 'Nenhuma',
    this.secondMeal = 'Nenhuma',
    this.hasCollection = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'dayType': dayType,
      'vehicleNumber': vehicleNumber,
      'startTime': startTime,
      'endTime': endTime,
      'int1Start': int1Start,
      'int1End': int1End,
      'int2Start': int2Start,
      'int2End': int2End,
      'regularHours': regularHours,
      'overtimeHours': overtimeHours,
      'intermitenciaHours': intermitenciaHours,
      'nightHours': nightHours,
      'hasMealAllowance': hasMealAllowance ? 1 : 0,
      'firstMeal': firstMeal,
      'secondMeal': secondMeal,
      'hasCollection': hasCollection ? 1 : 0,
    };
  }

  factory DriverEntry.fromMap(Map<String, dynamic> map) {
    return DriverEntry(
      id: map['id'],
      date: map['date'] ?? '',
      dayType: map['dayType'] ?? 'Util',
      vehicleNumber: map['vehicleNumber'] ?? '',
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'] ?? '',
      int1Start: map['int1Start'] ?? '',
      int1End: map['int1End'] ?? '',
      int2Start: map['int2Start'] ?? '',
      int2End: map['int2End'] ?? '',
      regularHours: (map['regularHours'] as num?)?.toDouble() ?? 0.0,
      overtimeHours: (map['overtimeHours'] as num?)?.toDouble() ?? 0.0,
      intermitenciaHours: (map['intermitenciaHours'] as num?)?.toDouble() ?? 0.0,
      nightHours: (map['nightHours'] as num?)?.toDouble() ?? 0.0,
      hasMealAllowance: (map['hasMealAllowance'] ?? 1) == 1,
      firstMeal: map['firstMeal'] ?? 'Nenhuma',
      secondMeal: map['secondMeal'] ?? 'Nenhuma',
      hasCollection: (map['hasCollection'] ?? 0) == 1,
    );
  }
}