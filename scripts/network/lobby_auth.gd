class_name LobbyAuth
extends RefCounted
## The password check done while a peer connects (SceneMultiplayer's
## authentication step), used by NetworkManager. Owned by networking.
## Sync: runs once per connection, before the peer counts as connected. The
## client sends a hash of the password; the host compares it with its own and
## answers OK or DENY. The hash keeps the password out of casual packet dumps;
## it is not encryption, which is fine for a LAN game.

const OK: PackedByteArray = [111, 107]
const DENY: PackedByteArray = [110, 111]
const OPEN: PackedByteArray = [0]
const SALT: String = "sinkhole:"


## An empty password means an open server. It hashes to a one-byte marker,
## because the engine refuses to send an empty authentication packet.
static func hash_password(password: String) -> PackedByteArray:
	if password.is_empty():
		return OPEN
	return (SALT + password).sha256_buffer()


## Whether the hash a joiner presented satisfies the host's.
static func accepts(host_hash: PackedByteArray, presented: PackedByteArray) -> bool:
	return host_hash == presented
