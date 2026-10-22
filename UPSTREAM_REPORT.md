# Copy-ready upstream report (not posted)

Repro (public, frozen at e79cf0561aee4d890e48c23e4e764a60ca9302ad): https://github.com/ricardoboss/kiota-dart-error-copywith-repro/tree/e79cf0561aee4d890e48c23e4e764a60ca9302ad

**Relevant trackers:** the reproduction concerns the interaction between generated models and the runtime adapter. A fix could be made on either side; coordinate any reports between:
- Generator (generated `copyWith` / constructors): https://github.com/microsoft/kiota/issues
- Runtime adapter (`HttpClientRequestAdapter`, `ApiException`): https://github.com/microsoft/kiota-dart/issues

**Title:** Dart: discriminated error models lose their concrete subtype and fields when the request adapter enriches them

**Versions:** Kiota 1.36.1; `microsoft_kiota_abstractions` 0.3.0 and 0.3.1 (0.3.1 is the latest on pub.dev at time of writing); `microsoft_kiota_http` 0.0.7;
`microsoft/kiota-dart` main at [b74e0c2](https://github.com/microsoft/kiota-dart/commit/b74e0c2b48f5d63ec3892c66367698c01e018b6c) still calls `copyWith`; Dart 3.13.5.

**Steps:** generate a client from `openapi.yaml` (error response schema with a `discriminator`; derived schemas via `allOf`),
call `client.things.getAsync()` against a 409 `application/problem+json` response whose `type` maps to `ConflictProblemDto`
and which contains `conflictId`.

**Expected:** the caught exception is a `ConflictProblemDto` with `conflictId`, `statusCode` 409 and response headers.

**Actual:** the caught exception is a plain `ProblemDetailsDto`; `statusCode`, headers and `additionalData` are set but the subtype and `conflictId` are gone.
`ConflictProblemDto.createFromDiscriminatorValue` / `ProblemDetailsDto.createFromDiscriminatorValue` do return the subtype when parsing directly (`direct-parse` line in the repro output),
so the type is lost after deserialization.
404 (`NotFoundProblemDto`) and 410 (`GoneProblemDto`) show the same erasure, but those subtypes add no fields, so only the runtime type differs.

**Analysis (repro-verified unless marked):**
- [`HttpClientRequestAdapter._throwIfFailedResponse`](https://github.com/microsoft/kiota-dart/blob/b74e0c2/packages/microsoft_kiota_http/lib/src/http_client_request_adapter.dart#L137-L141) replaces the deserialized `ApiException` with `apiException.copyWith(statusCode:, responseHeaders:)` before throwing.
- The generated base `ProblemDetailsDto.copyWith` constructs a `ProblemDetailsDto`; generated derived classes have no `copyWith` override and only a no-argument constructor (`ConflictProblemDto() : super()`).
- [`ApiException`](https://github.com/microsoft/kiota-dart/blob/b74e0c2/packages/microsoft_kiota_abstractions/lib/src/api_exception.dart#L15) `statusCode`/`responseHeaders` are `final`, so a derived class cannot simply be mutated by the adapter.
- Unverified scratch experiment (not in the repo): hand-adding a `copyWith` override to `ConflictProblemDto` preserved the subtype and `conflictId`, but `statusCode`/headers came out `null`
  because the derived constructor cannot forward them to `ApiException`. A complete fix therefore needs the generator (derived constructors/`copyWith` forwarding base fields)
  and/or the adapter (not replacing the instance), and which side should change is for the maintainers to decide.
- Unknown discriminator values (418 with no mapping) fall back to `ProblemDetailsDto` correctly; no loss there.

**Searched:** no existing issue found for `copyWith` or error subtype in `microsoft/kiota-dart` or `microsoft/kiota` (checked 2026-10-22).
