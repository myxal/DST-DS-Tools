#!/bin/bash
_plist_path=~/Library/LaunchAgents/dsa_snapshot.plist
_script_path=~/Applications/dsa_snapshot.sh
set -e
[ "$1" == "uninstall" ] && {
  echo "Uninstalling DSA Snapshotter"
  launchctl unload $_plist_path
  rm -i $_script_path $_plist_path
  exit
}
set -e
PATH=$PATH:/usr/libexec
which PlistBuddy >/dev/null || {
  echo "FATAL: PlistBuddy not found." >&2
  exit 1
}
_data_folders=()
while IFS= read -r -d $'\0' ; do
  _data_folders+=("$REPLY")
done < <(find  "$HOME/Library/Application Support/Steam/userdata" -type d -name 219740 -maxdepth 2 -print0)
_pbcommands=(
  'Clear dict'
  'Add :Label string "local.dontstarve.snapshot"'
  'Add :ThrottleInterval integer 20'
  'Add :ProgramArguments array'
  'Add :WatchPaths array'
  "Add :ProgramArguments:0 string $HOME/Applications/dsa_snapshot.sh"
)
for I in ${!_data_folders[@]}; do
  echo "Found DS data folder: ${_data_folders[$I]}"
  _pbcommands+=(
  "Add :WatchPaths:$I string \"${_data_folders[$I]}\""
  )
done
for I in ${!_pbcommands[@]}; do
  PlistBuddy -x -c "${_pbcommands[$I]}" $_plist_path >/dev/null
done
echo "Agent file created."
_payload_start=$(awk '/^__PAYLOAD_BELOW__/ {print NR + 1; exit 0; }' "$0")
tail -n+$_payload_start "$0" > $_script_path
chmod a+x $_script_path
launchctl load $_plist_path
echo "Agent loaded."
exit

__PAYLOAD_BELOW__
#!/bin/bash
set -e
# sleep for some time to let game finish writes
sleep 15
_sums_filename=".dsa_snapshot_md5"
function make_new_snapshot {
  ditto -c -k --sequesterRsrc --keepParent "remote" snapshot-$(date +%F-%H-%M).zip
  echo -n "$_new_sums" > "$_sums_filename"
}
_data_folders=()
while IFS= read -r -d $'\0' ; do
  _data_folders+=("$REPLY")
done < <(find  "$HOME/Library/Application Support/Steam/userdata" -type d -name 219740 -maxdepth 2 -print0)
[ ${#_data_folders[@]} -gt 0 ] || {
  echo "No data folders found!" >&2
  exit 1
}
shopt -s extglob
pgrep -xq dontstarve_steam && {
  for _i in ${!_data_folders[@]}; do
    cd "${_data_folders[$_i]}"
    _new_sums=$(md5 remote/*+(_[12345])?(_hamlet_beta_backup))
    # enable RE globbing
    # if the sums file doesn't exist, make a new snapshot without checking
    [ ! -f "$_sums_filename" ] && {
      make_new_snapshot
      continue
    }
    # compare and make new if required
    diff -q <(echo -n "$_new_sums") "$_sums_filename" >/dev/null || {
      make_new_snapshot
    }
  done
}
