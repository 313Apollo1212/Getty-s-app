enum AppRole {
  admin,
  employee;

  static AppRole fromString(String value) {
    return switch (value) {
      'admin' => AppRole.admin,
      _ => AppRole.employee,
    };
  }

  String get value => name;

  bool get isAdmin => this == AppRole.admin;
}
