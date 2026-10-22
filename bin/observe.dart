// Sends discriminated problem responses through the real HttpClientRequestAdapter
// (mock transport only) and prints what the caller catches.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiota_dart_error_copywith_repro/src/models/conflict_problem_dto.dart';
import 'package:kiota_dart_error_copywith_repro/src/models/problem_details_dto.dart';
import 'package:kiota_dart_error_copywith_repro/src/repro_client.dart';
import 'package:microsoft_kiota_abstractions/microsoft_kiota_abstractions.dart';
import 'package:microsoft_kiota_http/microsoft_kiota_http.dart';
import 'package:microsoft_kiota_serialization_json/microsoft_kiota_serialization_json.dart';

const _base = 'https://example.invalid/problems';

Future<void> main() async {
  // Control: the generated factory itself returns the concrete subtype.
  final body = utf8.encode(jsonEncode({
    'type': '$_base/conflict', 'title': 'Conflict', 'status': 409, 'conflictId': 'c-1',
  }));
  final direct = JsonParseNodeFactory()
      .getRootParseNode('application/json', Uint8List.fromList(body))
      .getObjectValue(ProblemDetailsDto.createFromDiscriminatorValue);
  print('direct-parse: runtimeType=${direct.runtimeType} '
      'conflictId=${direct is ConflictProblemDto ? direct.conflictId : "n/a"}');

  final cases = <(String, int, Map<String, Object?>)>[
    ('conflict-409', 409, {'type': '$_base/conflict', 'title': 'Conflict', 'status': 409, 'detail': 'd', 'conflictId': 'c-1', 'extra': 'x'}),
    ('not-found-404', 404, {'type': '$_base/not-found', 'title': 'Not found', 'status': 404}),
    ('gone-410-default', 410, {'type': '$_base/gone', 'title': 'Gone', 'status': 410}),
    ('unknown-type-418-default', 418, {'type': '$_base/other', 'title': 'Other', 'status': 418, 'extra': 'x'}),
  ];
  for (final (name, status, json) in cases) {
    final client = MockClient.streaming((request, _) async => http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(json))), status,
          headers: {'content-type': 'application/problem+json', 'x-request-id': 'req-$status'},
        ));
    final adapter = HttpClientRequestAdapter(
        authProvider: const AnonymousAuthenticationProvider(), client: client);
    adapter.baseUrl = 'https://example.invalid';
    try {
      await ReproClient(adapter).things.getAsync();
      print('$name: no exception');
    } on ApiException catch (e) {
      final p = e is ProblemDetailsDto ? e : null;
      print('$name: runtimeType=${e.runtimeType} statusCode=${e.statusCode} '
          'x-request-id=${e.responseHeaders?['x-request-id']} title=${p?.title} '
          'additionalData=${p?.additionalData} '
          'conflictId=${e is ConflictProblemDto ? e.conflictId : "n/a"}');
    }
  }
}
