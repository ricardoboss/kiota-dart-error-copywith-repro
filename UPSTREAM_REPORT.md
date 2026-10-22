# Copy-ready upstream report (not posted)

Repro: https://github.com/ricardoboss/kiota-dart-error-copywith-repro (commit: fill in merged SHA)

**Title:** Dart: discriminated error models lose their concrete subtype when the request adapter enriches them

**Versions:** Kiota 1.36.1; `microsoft_kiota_abstractions` 0.3.0 and 0.3.1; `microsoft_kiota_http` 0.0.7
(latest on pub.dev and `microsoft/kiota-dart` main at b74e0c2 still calls `copyWith`); Dart 3.13.5.

**Steps:** generate a client from `openapi.yaml` (error response schema with a `discriminator`; derived schemas via `allOf`),
call `client.things.getAsync()` against a 409 `application/problem+json` response whose `type` maps to `ConflictProblemDto`
and which contains `conflictId`.

**Expected:** the caught exception is a `ConflictProblemDto` with `conflictId`, `statusCode` 409 and response headers.

**Actual:** the caught exception is a plain `ProblemDetailsDto`; `statusCode`, headers and `additionalData` are set but the subtype and `conflictId` are gone.
`ConflictProblemDto.createFromDiscriminatorValue` / `ProblemDetailsDto.createFromDiscriminatorValue` do return the subtype when parsing directly (`direct-parse` line in the repro output),
so the type is lost after deserialization.

**Analysis (limited to what the repro shows):**
- `HttpClientRequestAdapter._throwIfFailedResponse` replaces the deserialized `ApiException` with `apiException.copyWith(statusCode:, responseHeaders:)` before throwing
  (`http_client_request_adapter.dart`, ~L138).
- The generated base `ProblemDetailsDto.copyWith` constructs a `ProblemDetailsDto`; generated derived classes have no `copyWith` override and only a no-argument constructor (`ConflictProblemDto() : super()`).
- `ApiException`'s `statusCode`/`responseHeaders` are `final`, so a derived class cannot simply be mutated by the adapter.
- Control (scratch, not in the repo): hand-adding a `copyWith` override to `ConflictProblemDto` preserves the subtype and `conflictId`, but `statusCode`/headers then come out `null`
  because the derived constructor cannot forward them to `ApiException`. A complete fix therefore needs the generator (derived constructors/`copyWith` forwarding base fields)
  and/or the adapter (not replacing the instance), and which side should change is for the maintainers to decide.
- Unknown discriminator values fall back to `ProblemDetailsDto` correctly; no loss there.

**Searched:** no existing issue found in `microsoft/kiota` or `microsoft/kiota-dart` for `copyWith` / error subtype (checked 2026-10-22).
Kiota 1.35.0 additionally fails to compile this pattern (fixed in 1.36.0); see the separate discriminator repro.
