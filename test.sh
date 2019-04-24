#!/bin/bash


### Convenience functions

if tty -s; then
	info_prefix="\x1b[33m>>>\x1b[0m"
	fail_prefix="\x1b[31mTEST FAILED:\x1b[0m"
	success_msg="\x1b[32mALL TESTS PASSED!\x1b[0m"
else
	info_prefix=">>>"
	fail_prefix="TEST FAILED:"
	success_msg="ALL TESTS PASSED!"
fi

break_to_shell() {
	( cd $tmpdir && ${SHELL:-bash} -i; )
}

step() {
	printf "$info_prefix %s...\n" "$*"
}

fail() {
	printf "$fail_prefix %s!\n" "$*" >&2
	[ -n "$BREAK" ] && break_to_shell
	exit 1
}

success() {
	echo -e "$success_msg"
	exit 0
}

v() {
	if [ -n "$VERBOSE" ]; then
		echo "$@" >&2
	fi
	"$@"
}

### Ensure we clean up after ourselves

tmpdir=
devname="luks-test-$RANDOM"
dm_target="/dev/mapper/$devname"
cleanup() {
	[ -b "$dm_target" ] && cryptsetup close "$devname"
	[ -d "$tmpdir" ] && rm -rf "$tmpdir"
}
trap cleanup EXIT


### Run some basic functional tests

tmpdir=$(mktemp -d) \
|| fail 'unable to make tmp dir'

disk="$tmpdir/disk"
header="$tmpdir/header"
secrets="$tmpdir/secrets"
secrets_blocks='bs=1M count=1'

password=hunter2 # ;)
nuke=123456

create_disk() {
	step 'Making a temporary "disk" for testing'
	v truncate -s 8M "$disk" \
	  || fail 'unable to make test disk'
}

create_secrets() {
	step 'Creating some dummy secret data'
	v dd if=/dev/urandom of="$secrets" $secrets_blocks && test -s "$secrets" \
	  || fail 'unable to create secrets file'
}

luksFormat() {
	step 'Initializing LUKS container'
	v cryptsetup luksFormat "$disk" <<< "$password" \
	  || fail 'unable to format LUKS container'
}

luksOpen() {
	step 'Opening with correct passphrase'
	v cryptsetup luksOpen "$disk" "$devname" <<< "$password" \
	  && test -b "$dm_target" \
	  || fail 'disk failed to open'
}

luksOpen_fail() {
	step 'Opening with correct passphrase, expecting failure'
	! v cryptsetup luksOpen "$disk" "$devname" <<< "$password" \
	  || fail "disk opened when it shouldn't have been able to!"
}

luksOpen_wrong() {
	step 'Trying to open with wrong passphrase'
	! v cryptsetup luksOpen "$disk" "$devname" <<< "wrong $password" \
	  || fail 'disk opened with wrong passphrase!?'
}

luksOpen_nuke() {
	step 'Opening with nuke passphrase'
	! v cryptsetup luksOpen "$disk" "$devname" <<< "$nuke" \
	  && ! test -e "$dm_target" \
	  || fail 'luksOpen with nuke passphrase exited zero!?'
}

luksClose() {
	step 'Closing LUKS container'
	v cryptsetup close "$devname" \
	  || fail 'unable to close LUKS container'
}

luksHeaderBackup() {
	step 'Making header backup'
	v cryptsetup luksHeaderBackup "$disk" --header-backup-file "$header" \
	  || fail 'unable to make LUKS header backup'
}

luksHeaderRestore() {
	step 'Restoring header backup'
	# stdin from /dev/null to not ask "Are you sure? (Type uppercase yes):"
	v cryptsetup luksHeaderRestore "$disk" --header-backup-file "$header" \
	  </dev/null \
	  || fail 'unable to restore LUKS header backup'
}

luksAddNuke() {
	step 'Adding nuke key'
	v cryptsetup --key-file <(echo -n "$password") \
		luksAddNuke "$disk" <<< "$nuke" \
	  || fail 'failed to add nuke key'
}

has_key() {
	v cryptsetup luksDump disk | v grep -xq 'Key Slot [0-9]*: ENABLED'
}

verify_has_key() {
	step 'Making sure there exists at least one key slot'
	has_key || fail 'there are no key slots'
}

verify_no_keys() {
	step 'Making sure there are no key slots'
	! has_key || fail 'there are no key slots'
}

write_secrets() {
	step 'Writing secret data into LUKS container'
	v dd if="$secrets" of="$dm_target" conv=nocreat \
	  || fail 'unable to copy secrets into LUKS container'
}

verify_secrets() {
	step 'Verifying secret data in LUKS container'
	v diff -u --label 'expected-secrets' --label 'found-secrets' \
	  <(dd if="$secrets" $secrets_blocks | hexdump -C | head; echo ...) \
	  <(dd if="$dm_target" $secrets_blocks | hexdump -C | head; echo ...) \
	  || fail 'Secrets differ!'
}

create_disk
create_secrets
luksFormat
luksOpen_wrong
luksOpen
write_secrets
verify_secrets
luksClose
luksHeaderBackup
luksAddNuke
luksOpen
verify_secrets
luksClose
verify_has_keys
luksOpen_nuke
verify_no_keys
luksOpen_fail
luksHeaderRestore
verify_has_keys
luksOpen
verify_secrets
luksClose

success
