import 'package:intl/intl.dart';

final _dateTimeFormat = DateFormat('MMM d, yyyy h:mm a');

String formatDateTime(DateTime value) =>
    _dateTimeFormat.format(value.toLocal());
