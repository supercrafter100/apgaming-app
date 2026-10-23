/// Runs two futures in parallel and rethrows the first error as-is (record `.wait`
/// would wrap it in a ParallelWaitError, hiding the ApiException).
Future<(A, B)> both<A, B>(Future<A> a, Future<B> b) async {
  final results = await Future.wait<Object?>([a, b]);
  return (results[0] as A, results[1] as B);
}
