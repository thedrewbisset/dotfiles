# Disk encryption on Windows

Why a Windows machine in this setup wants full-disk encryption, and the order that
works. Nothing here is a recipe: every step is manual on purpose, and two of them
can only be done at the machine's own keyboard.

## Why

A key-based SSH logon session cannot reach Windows Credential Manager -- it reports
"Credentials cannot be saved from this logon session". Tools that would otherwise use
it fall back to a file, so `gh` keeps its token as plaintext under its config
directory.

File permissions still apply, so that file is readable only by the user,
Administrators and SYSTEM. But permissions are enforced by the running OS, and an
unencrypted drive does not need the OS to be read: anyone holding the disk reads the
token and everything else on it. Encryption is what makes the permissions mean
something off the machine, and it brings a token on disk roughly back to the safety
of one in Credential Manager.

This matters more on a machine that is reached over SSH, because that is exactly the
session type that forces the plaintext fallback.

## Requirements

Device encryption on Windows 11 **Home** needs both a TPM and Secure Boot. With
either missing the Settings option does not appear at all, which reads as an
unsupported machine rather than an unmet requirement. Check both before concluding
anything:

```powershell
Get-Tpm | Select TpmPresent, TpmReady, TpmEnabled
Confirm-SecureBootUEFI    # True when on; throws when the machine booted legacy/CSM
```

Pro and above have BitLocker proper and do not depend on the Settings toggle.

## Do the first two steps at the console

Secure Boot can only be changed in firmware setup, which SSH cannot reach. More
importantly, if the TPM fails to release the key after a reboot the machine stops at
a BitLocker recovery-key prompt *before* Windows starts -- no network, no SSH, and
the box simply never comes back until someone types the key at the keyboard. Be at
the machine, with the recovery key already saved somewhere else.

## Steps

1. **Turn on Secure Boot** in firmware setup, making sure the boot mode is UEFI and
   not legacy/CSM. Switching an installed Windows from legacy to UEFI needs the disk
   converted to GPT first (`mbr2gpt`), so check the current mode before changing it.
   Confirm with `Confirm-SecureBootUEFI` once Windows is back.
2. **Turn on Device encryption** -- Settings > Privacy & security > Device
   encryption. A Microsoft account sign-in is what backs the recovery key up
   automatically; a local account leaves you to save it yourself.
3. **Confirm the recovery key is actually backed up** before relying on any of this,
   and note the key ID per drive. A key that exists only on the encrypted disk is not
   a backup.
4. **Check every fixed drive**, not just C:. A Dev Drive (step 2 of the
   [runbook](windows.md)) is a separate volume and may need turning on on its own.

## Verify

Read-only, and works over SSH afterwards:

```powershell
manage-bde -status
```

Expect `Conversion Status: Fully Encrypted` and `Protection Status: Protection On`
for each drive. `Used Space Only` encryption is normal for Device encryption and
covers everything written afterwards.

## Reduce what a token is worth

Encryption protects the disk at rest; it does nothing once the machine is running and
unlocked. Narrowing the credential is the other half, and is worth doing regardless:

- Prefer a fine-grained personal access token scoped to the repositories it needs,
  loaded with `gh auth login --with-token`, over the broad `repo` + `workflow` scopes
  an OAuth web login grants.
- Know where to revoke it: GitHub > Settings > Applications > Authorized OAuth Apps
  for a web login, or the token's own page for a PAT.
