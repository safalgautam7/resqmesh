class User {
  final int id;
  final String username;
  final String? email;
  final String role;
  final String? firstName;
  final String? lastName;

  User({
    required this.id,
    required this.username,
    this.email,
    required this.role,
    this.firstName,
    this.lastName,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        username: json['username'] as String,
        email: json['email'] as String?,
        role: json['role'] as String? ?? 'CITIZEN',
        firstName: json['first_name'] as String?,
        lastName: json['last_name'] as String?,
      );

  bool get isCoordinator => role == 'COORDINATOR' || role == 'ADMIN';
}
