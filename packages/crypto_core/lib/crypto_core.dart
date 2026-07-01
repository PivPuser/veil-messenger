/// crypto_core — end-to-end encryption core for the anonymous messenger.
///
/// Public surface:
///   * [Identity]  — a user's long-term key material (no phone/e-mail).
///   * [PreKeys]   — signed + one-time pre-keys published by the responder.
///   * [InviteKey] — the shareable "key" (contact invitation), `amk1:...`.
///   * [Session]   — an established 1:1 E2E session (X3DH + Double Ratchet).
///
/// Lower-level building blocks ([X3dh], [DoubleRatchet], [Primitives]) are also
/// exported for tests and advanced use.
library crypto_core;

export 'src/double_ratchet.dart' show DoubleRatchet, RatchetHeader;
export 'src/identity.dart' show Identity, PreKeys;
export 'src/invite.dart' show InviteKey;
export 'src/primitives.dart' show Primitives;
export 'src/safety_number.dart' show SafetyNumber;
export 'src/secret_vault.dart' show SecretVault;
export 'src/session.dart' show Session;
export 'src/x3dh.dart' show X3dh, InitialHandshake;
