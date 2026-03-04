import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../models/profile.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';

enum _UserViewFilter { all, admins, employees }

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  late Future<List<Profile>> _usersFuture;
  final TextEditingController _searchController = TextEditingController();
  _UserViewFilter _viewFilter = _UserViewFilter.all;

  @override
  void initState() {
    super.initState();
    _usersFuture = widget.service.fetchAllUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _usersFuture = widget.service.fetchAllUsers(forceRefresh: true);
    });
  }

  Future<void> _openCreateUserDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateUserDialog(service: widget.service),
    );

    if (created == true && mounted) {
      await _reload();
    }
  }

  Future<void> _openResetPasswordDialog(Profile profile) async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ResetPasswordDialog(service: widget.service, profile: profile),
    );

    if (reset == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset for ${profile.username}.')),
      );
    }
  }

  Future<void> _deleteUser(Profile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Delete ${profile.fullName} (@${profile.username})? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.service.deleteUser(userId: profile.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted @${profile.username}.')));
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _onUserMenuSelected(
    _UserMenuAction action,
    Profile profile,
    bool isCurrentUser,
  ) async {
    switch (action) {
      case _UserMenuAction.resetPassword:
        await _openResetPasswordDialog(profile);
      case _UserMenuAction.delete:
        if (isCurrentUser) {
          return;
        }
        await _deleteUser(profile);
    }
  }

  List<Profile> _applyUserFilters(List<Profile> users, String? viewerId) {
    final query = _searchController.text.trim().toLowerCase();

    var result = viewerId == null
        ? users
        : users.where((user) => user.id != viewerId).toList();

    switch (_viewFilter) {
      case _UserViewFilter.admins:
        result = result.where((u) => u.role == AppRole.admin).toList();
      case _UserViewFilter.employees:
        result = result.where((u) => u.role == AppRole.employee).toList();
      case _UserViewFilter.all:
        break;
    }

    if (query.isNotEmpty) {
      result = result.where((user) {
        final roleLabel = user.role == AppRole.admin ? 'admin' : 'employee';
        return user.fullName.toLowerCase().contains(query) ||
            user.username.toLowerCase().contains(query) ||
            roleLabel.contains(query);
      }).toList();
    }

    result.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
    return result;
  }

  Widget _buildFilterChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Profile>>(
          future: _usersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                padding: appPagePadding,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(snapshot.error.toString()),
                    ),
                  ),
                ],
              );
            }

            final users = snapshot.data ?? const [];
            final viewerId = widget.service.currentUser?.id;
            final visibleUsers = viewerId == null
                ? users
                : users.where((user) => user.id != viewerId).toList();
            final adminCount = visibleUsers
                .where((u) => u.role == AppRole.admin)
                .length;
            final employeeCount = visibleUsers.length - adminCount;
            final filteredUsers = _applyUserFilters(users, viewerId);

            return ListView(
              padding: appPagePadding,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Users',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _openCreateUserDialog,
                              icon: const Icon(
                                Icons.person_add_alt_1,
                                size: 18,
                              ),
                              label: const Text('Add'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search users',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildFilterChip(
                              'All (${visibleUsers.length})',
                              _viewFilter == _UserViewFilter.all,
                              () => setState(
                                () => _viewFilter = _UserViewFilter.all,
                              ),
                            ),
                            _buildFilterChip(
                              'Admins ($adminCount)',
                              _viewFilter == _UserViewFilter.admins,
                              () => setState(
                                () => _viewFilter = _UserViewFilter.admins,
                              ),
                            ),
                            _buildFilterChip(
                              'Employees ($employeeCount)',
                              _viewFilter == _UserViewFilter.employees,
                              () => setState(
                                () => _viewFilter = _UserViewFilter.employees,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${filteredUsers.length} shown',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (filteredUsers.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No users match your filters.'),
                    ),
                  )
                else
                  ...filteredUsers.map((profile) {
                    final isAdmin = profile.role == AppRole.admin;
                    final isCurrentUser = viewerId == profile.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Text(
                            profile.fullName.isEmpty
                                ? '?'
                                : profile.fullName[0].toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          profile.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          '@${profile.username} · ${isAdmin ? 'Admin' : 'Employee'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<_UserMenuAction>(
                          tooltip: 'Actions',
                          onSelected: (action) => _onUserMenuSelected(
                            action,
                            profile,
                            isCurrentUser,
                          ),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: _UserMenuAction.resetPassword,
                              child: _MenuItem(
                                icon: Icons.lock_reset_rounded,
                                label: 'Reset Password',
                              ),
                            ),
                            PopupMenuItem(
                              value: _UserMenuAction.delete,
                              enabled: !isCurrentUser,
                              child: _MenuItem(
                                icon: Icons.delete_outline_rounded,
                                label: isCurrentUser
                                    ? 'Cannot Delete Yourself'
                                    : 'Delete User',
                                color: isCurrentUser
                                    ? null
                                    : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _UserMenuAction { resetPassword, delete }

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.service});

  final SupabaseService service;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  AppRole _role = AppRole.employee;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.service.createUser(
        username: _usernameController.text,
        password: _passwordController.text,
        fullName: _nameController.text,
        role: _role.value,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create User'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Full name is required.';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Username is required.';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Password must be at least 6 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AppRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(
                    value: AppRole.employee,
                    child: Text('Employee'),
                  ),
                  DropdownMenuItem(value: AppRole.admin, child: Text('Admin')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _role = value);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.service, required this.profile});

  final SupabaseService service;
  final Profile profile;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.service.resetUserPassword(
        userId: widget.profile.id,
        newPassword: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset Password: ${widget.profile.username}'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _passwordController,
          decoration: const InputDecoration(labelText: 'New Password'),
          obscureText: true,
          validator: (value) {
            if (value == null || value.length < 6) {
              return 'Password must be at least 6 characters.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Reset'),
        ),
      ],
    );
  }
}
