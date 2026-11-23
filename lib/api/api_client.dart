import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}

/// Thin JSON client for the NestJS backend. Authenticates with the bearer token
/// that the mobile login handoff produced.
class ApiClient {
  ApiClient({required this.baseUrl, required this.onUnauthorized, http.Client? httpClient})
    : httpClient = httpClient ?? http.Client();

  final String baseUrl;

  /// Called with the server's reason, already translated, when a request with a session is refused.
  final void Function(String message) onUnauthorized;

  /// Sends the requests; the demo swaps this for an in-memory backend.
  http.Client httpClient;

  String? token;

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await httpClient.send(request).timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw ApiException('Kan geen verbinding maken met de Gaming Hub. Controleer je internet.');
    }

    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final message = _errorMessage(decoded, response.statusCode);
    if (response.statusCode == 401 && token != null) onUnauthorized(message);
    throw ApiException(message, statusCode: response.statusCode);
  }

  static dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }

  // NestJS errors look like { message: string | string[], error, statusCode }
  static String _errorMessage(dynamic body, int status) {
    final message = body is Map ? body['message'] : null;
    if (message is String && message.isNotEmpty) return translateApiMessage(message);
    if (message is List && message.isNotEmpty) return message.map((m) => translateApiMessage('$m')).join('\n');
    return switch (status) {
      401 => 'Je sessie is verlopen. Log opnieuw in.',
      403 => 'Je hebt geen toegang tot deze actie.',
      404 => 'Niet gevonden.',
      _ => 'Er ging iets mis ($status). Probeer het later opnieuw.',
    };
  }
}

/// The backend answers in English; members see Dutch everywhere else on the platform.
/// What a blocked person sees when the backend refuses them.
const accountBlockedMessage =
    'Je account is geblokkeerd door het team van de AP Gaming Hub. Spreek een medewerker aan of contacteer ons via Discord.';

/// The blocked message with the end of the block, when the backend told us.
String accountBlockedUntil(DateTime? until) => until == null
    ? accountBlockedMessage
    : 'Je account is geblokkeerd door het team van de AP Gaming Hub tot ${DateFormat('d MMMM y, HH:mm', 'nl_BE').format(until.toLocal())}. '
          'Spreek een medewerker aan of contacteer ons via Discord.';

String translateApiMessage(String message) {
  const known = {
    'Cannot reserve in the past': 'Je kan niet reserveren in het verleden.',
    'Reservations can only be made for today or the next open day':
        'Je kan alleen reserveren voor vandaag of de eerstvolgende open dag.',
    'A reservation must last 1, 1.5 or 2 hours': 'Een reservatie duurt 1, 1,5 of 2 uur.',
    'You already have a reservation that overlaps with this time slot':
        'Je hebt al een reservatie die overlapt met dit tijdslot.',
    'Reservation is already cancelled': 'Deze reservatie is al geannuleerd.',
    'You cannot cancel a reservation that has already started or passed':
        'Je kan geen reservatie annuleren die al begonnen of voorbij is.',
    'Reservations require a Microsoft account': 'Je kan alleen reserveren met je AP Microsoft-account.',
    'This time slot is already reserved': 'Dit tijdslot is al gereserveerd.',
    'Reservation not found': 'Reservatie niet gevonden.',
    'Invalid or expired login code': 'Inloggen is verlopen. Probeer opnieuw.',
    'Unauthorized': 'Je sessie is verlopen. Log opnieuw in.',
    'Invalid or expired authentication token': 'Je sessie is verlopen. Log opnieuw in.',
    'Account blocked': accountBlockedMessage,
  };
  if (known.containsKey(message)) return known[message]!;
  final gap = RegExp(r'^You must have at least (\d+) minutes between reservations$').firstMatch(message);
  if (gap != null) return 'Er moet minstens ${gap[1]} minuten tussen je reservaties zitten.';
  final perDay = RegExp(r'^You can only make (\d+) reservations? per day$').firstMatch(message);
  if (perDay != null) {
    return perDay[1] == '1'
        ? 'Je kan maximaal 1 reservatie per dag maken.'
        : 'Je kan maximaal ${perDay[1]} reservaties per dag maken.';
  }
  if (message.startsWith('You already have three no-shows')) {
    return 'Je hebt al drie no-shows dit semester. Je kan pas opnieuw reserveren vanaf het volgende semester.';
  }
  if (message.startsWith('All ') && message.endsWith('are already reserved for this time slot')) {
    return 'Alle toestellen van dit type zijn al gereserveerd op dit moment.';
  }
  return message;
}
