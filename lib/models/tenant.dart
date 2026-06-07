class TenantMembership {
  final String tenantId;
  final String tenantName;
  final String role;
  final String status;

  const TenantMembership({
    required this.tenantId,
    required this.tenantName,
    required this.role,
    required this.status,
  });

  factory TenantMembership.fromMap(Map<String, dynamic> map) {
    return TenantMembership(
      tenantId: map['tenantId'] ?? '',
      tenantName: map['tenantName'] ?? '이름 없는 가게',
      role: map['role'] ?? 'viewer',
      status: map['status'] ?? 'inactive',
    );
  }
}
