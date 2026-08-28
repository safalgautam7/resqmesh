import 'package:flutter/material.dart';

const kPrimary = Color(0xFFB71C1C); // emergency red
const kDark = Color(0xFF212121);
const kAmber = Color(0xFFFFA000);

ThemeData buildResqTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimary,
      primary: kPrimary,
    ),
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: kDark,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

Color priorityColor(String priority) {
  switch (priority) {
    case 'CRITICAL':
      return Colors.red;
    case 'HIGH':
      return Colors.orange;
    case 'MEDIUM':
      return Colors.amber;
    case 'LOW':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

Color severityColor(String severity) {
  switch (severity) {
    case 'CRITICAL':
      return Colors.red;
    case 'HIGH':
      return Colors.deepOrange;
    case 'WARNING':
      return Colors.amber;
    default:
      return Colors.blueGrey;
  }
}
