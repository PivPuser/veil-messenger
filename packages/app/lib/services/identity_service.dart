import 'package:crypto_core/crypto_core.dart';

/// Holds the user's long-term [Identity].
///
/// For now the identity is generated once per app session and kept in memory.
/// TODO: persist it through [SecretVault] + file storage so it survives
/// restarts, and (when the passcode lock is on) seal it under the password key.
class IdentityService {
  IdentityService._();

  static final IdentityService instance = IdentityService._();

  Identity? _identity;

  Future<Identity> identity() async => _identity ??= await Identity.generate();
}
