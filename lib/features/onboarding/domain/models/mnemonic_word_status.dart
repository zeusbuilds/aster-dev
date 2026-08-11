/// Per-field vocabulary status shown while a recovery phrase is entered.
enum MnemonicWordStatus { empty, valid, invalid }

/// SDK-authoritative full-phrase checksum state.
enum MnemonicChecksumStatus { incomplete, checking, valid, invalid }
