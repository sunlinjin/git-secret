#!/usr/bin/env bash

# shellcheck disable=2016
AWK_GPG_KEY_CNT='
BEGIN { cnt=0; OFS=":"; FS=":"; }
flag=0; $1 == "pub" { cnt++ }
END { print cnt }
'

function get_gpg_key_count {
  local gpg_local
  gpg_local=$(_get_gpg_local)
  $gpg_local --list-public-keys --with-colon | gawk "$AWK_GPG_KEY_CNT"
}

function tell {
  local emails
  local self_email=0
  local homedir

  # A POSIX variable
  # Reset in case getopts has been used previously in the shell.
  OPTIND=1

  while getopts "hmd:" opt; do
    case "$opt" in
      h) _show_manual_for "tell";;

      m) self_email=1;;

      d) homedir=$OPTARG;;

      *) _invalid_option_for 'tell';;
    esac
  done

  shift $((OPTIND-1))
  [ "$1" = "--" ] && shift

  # Validates that application is inited:
  _secrets_dir_exists

  # Command logic:
  emails=( "$@" )
  local git_email

  if [[ "$self_email" -eq 1 ]]; then
    git_email=$(git config user.email)

    if [[ -z "$git_email" ]]; then
      _abort "'git config user.email' is not set."
    fi

    emails+=("$git_email")
  fi

  if [[ "${#emails[@]}" -eq 0 ]]; then
    # If after possible addition of git_email, emails are still empty,
    # we should raise an exception.
    _abort "you must provide at least one email address."
  fi

  local start_key_cnt
  start_key_cnt=$(get_gpg_key_count)
  for email in "${emails[@]}"; do
    # This file will be removed automatically:
    _temporary_file  # note, that `_temporary_file` will export `filename` var.
    # shellcheck disable=2154
    local keyfile="$filename"

    if [[ -z "$homedir" ]]; then
      $SECRETS_GPG_COMMAND --export -a "$email" > "$keyfile"
    else
      # It means that homedir is set as an extra argument via `-d`:
      $SECRETS_GPG_COMMAND --no-permission-warning --homedir="$homedir" \
        --export -a "$email" > "$keyfile"
    fi

    if [[ ! -s "$keyfile" ]]; then
      _abort "no keyfile found for '$email'. Check your key name: 'gpg --list-keys'."
    fi

    # Importing public key to the local keychain:
    local gpg_local
    gpg_local=$(_get_gpg_local)
    $gpg_local --import "$keyfile" > /dev/null 2>&1
  done

  echo "done. ${emails[*]} added as someone who know(s) the secret."

  # force re-encrypting of files if required
  local fsdb
  local end_key_cnt
  fsdb=$(_get_secrets_dir_paths_mapping)
  end_key_cnt=$(get_gpg_key_count)
  [[ $start_key_cnt -ne $end_key_cnt ]] && _fsdb_clear_hashes "$fsdb"
}
