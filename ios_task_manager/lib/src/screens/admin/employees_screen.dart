import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../models/profile.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  late Future<List<Profile>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = widget.service.fetchAllUsers();
  }

  Future<void> _reload() async {
    setState(() {
      _usersFuture = widget.service.fetchAllUsers();
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

            return ListView.separated(
              padding: appPagePadding,
              itemCount: visibleUsers.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  avatar: const Icon(
                                    Icons.groups_2_outlined,
                                    size: 16,
                                  ),
                                  label: Text('Users ${visibleUsers.length}'),
                                ),
                                Chip(
                                  avatar: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                    size: 16,
                                  ),
                                  label: Text('Admins $adminCount'),
                                ),
                                Chip(
                                  avatar: const Icon(
                                    Icons.badge_outlined,
                                    size: 16,
                                  ),
                                  label: Text('Employees $employeeCount'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _openCreateUserDialog,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Add User'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final profile = visibleUsers[index - 1];
                final isAdmin = profile.role == AppRole.admin;
                final isCurrentUser = viewerId == profile.id;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.fullName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text('@${profile.username}'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(label: Text(isAdmin ? 'Admin' : 'Employee')),
                        PopupMenuButton<_UserMenuAction>(
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
                      ],
                    ),
                  ),
                );
              },
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
