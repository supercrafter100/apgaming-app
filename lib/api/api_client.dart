import 'dart:convert';

import 'package:http/http.dart' as http;

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
    : _http = httpClient ?? http.Client();

  final String baseUrl;
  final void Function() onUnauthorized;
  final http.Client _http;

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
      response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw ApiException('Kan geen verbinding maken met de Gaming Hub. Controleer je internet.');
    }

    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    if (response.statusCode == 401 && token != null) onUnauthorized();
    throw ApiException(_errorMessage(decoded, response.statusCode), statusCode: response.statusCode);
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
String translateApiMessage(String message) {
  const known = {
    'Cannot reserve in the past': 'Je kan niet reserveren in het verleden.',
    'Reservations can only be made up to 3 days in advance': 'Je kan maximaal 3 dagen op voorhand reserveren.',
    'You already have a reservation that overlaps with this time slot':
        'Je hebt al een reservatie die overlapt met dit tijdslot.',
    'You must have at least 30 minutes between reservations':
        'Er moet minstens 30 minuten tussen je reservaties zitten.',
    'You can only make two reservations per day': 'Je kan maximaal twee reservaties per dag maken.',
    'Reservation is already cancelled': 'Deze reservatie is al geannuleerd.',
    'You cannot cancel a reservation that has already started or passed':
        'Je kan geen reservatie annuleren die al begonnen of voorbij is.',
    'Cannot unlink your only sign-in provider': 'Je kan je enige login-methode niet ontkoppelen.',
    'This time slot is already reserved': 'Dit tijdslot is al gereserveerd.',
    'Reservation not found': 'Reservatie niet gevonden.',
    'Invalid or expired login code': 'Inloggen is verlopen. Probeer opnieuw.',
    'Unauthorized': 'Je sessie is verlopen. Log opnieuw in.',
    'Invalid or expired authentication token': 'Je sessie is verlopen. Log opnieuw in.',
  };
  if (known.containsKey(message)) return known[message]!;
  if (message.startsWith('You already have three no-shows')) {
    return 'Je hebt al drie no-shows dit semester. Je kan pas opnieuw reserveren vanaf het volgende semester.';
  }
  if (message.startsWith('All ') && message.endsWith('are already reserved for this time slot')) {
    return 'Alle toestellen van dit type zijn al gereserveerd op dit moment.';
  }
  return message;
}
