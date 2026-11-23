# Phase 17 secure session verification

Unreadable vault data fails closed. Logout attempts to clear the vault even when the stored value could not be read. The regression case uses a synthetic vault. Android Keystore read, write, restart and cleanup still require the isolated device journey.

When restoration fails, the account page offers Clear saved session. A Flutter widget test verifies the control and return to guest mode. A separate unit test verifies fail-closed behavior and cleanup after a read error.
