#!/usr/bin/env bash

JSON_DIR="/mnt/nixpkgs-json"
SELECTED_PNAMES=("python3" "rustc" "nodejs" "ruby" "php-with-extensions" "openjdk")
VERSIONS_DIR=/mnt/nixpkgs-versions
VERSIONS_DIR_FILTERED=/mnt/nixpkgs-versions-filtered
VERSION_RANGES_DIR=/mnt/nixpkgs-version-ranges

mkdir $VERSIONS_DIR
rm "$VERSIONS_DIR"/*

for JSON_FILE in "$JSON_DIR"/*.json; do
	echo "$JSON_FILE"
	FILENAME=$(basename -- "$JSON_FILE")
	INDEX=$(echo "$FILENAME" | sed -E 's/^([^-]+)-[^-_.]+(_diff)?\.json$/\1/')
	NIXPKGS_REV=$(echo "$FILENAME" | sed -E 's/^[^-]+-([^-_]+)(_diff)?\.json$/\1/')

	jq -r --argjson selected_pnames "$(printf '%s\n' "${SELECTED_PNAMES[@]}" | jq -R . | jq -s .)" \
		'to_entries[] | select(.value.pname as $pname | $selected_pnames | index($pname)) | "\(.key) \(.value.name) \(.value.pname) \(.value.version)"' \
		"$JSON_FILE" | while read -r ATTRNAME NAME PNAME VERSION; do
		if [[ ! -f "$VERSIONS_DIR/$PNAME" ]]; then
				echo "$ATTRNAME $VERSION $INDEX $NIXPKGS_REV" > "$VERSIONS_DIR/$PNAME"
		# if the last version of $pname recorded has a different version than $version
		elif ! grep "^$ATTRNAME " "$VERSIONS_DIR/$PNAME" | tail -n 1 | grep -q "$ATTRNAME $VERSION "; then
				echo "$ATTRNAME $VERSION $INDEX $NIXPKGS_REV" >> "$VERSIONS_DIR/$PNAME"
		fi
	done
done

FINAL_JSON_FILENAME="$(ls "$JSON_DIR" | tail -n 1)"
FINAL_INDEX=$(echo "$FINAL_JSON_FILENAME" | sed -E 's/^([^-]+)-[^-_.]+(_diff)?\.json$/\1/')
FINAL_NIXPKGS_REV=$(echo "$FINAL_JSON_FILENAME" | sed -E 's/^[^-]+-([^-_]+)(_diff)?\.json$/\1/')

mkdir $VERSIONS_DIR_FILTERED
rm "$VERSIONS_DIR_FILTERED"/*

sed '/^nodejs/!d' "$VERSIONS_DIR/nodejs" > "$VERSIONS_DIR_FILTERED/nodejs"
sed '/^jdk/!d' "$VERSIONS_DIR/openjdk" > "$VERSIONS_DIR_FILTERED/openjdk"
sed '/^python3/!d' "$VERSIONS_DIR/python3" | sed '/Package/d; /Full/d' > "$VERSIONS_DIR_FILTERED/python3"
sed '/Minimal/d' "$VERSIONS_DIR/ruby" > "$VERSIONS_DIR_FILTERED/ruby"
sed '/^rustc /!d' "$VERSIONS_DIR/rustc" > "$VERSIONS_DIR_FILTERED/rustc"

mkdir $VERSION_RANGES_DIR
rm "$VERSION_RANGES_DIR"/*

for FILE in "$VERSIONS_DIR_FILTERED"/*; do
	echo "$FILE"
	PNAME=$(basename -- "$FILE")
	for ATTRNAME in $(cut -d ' ' -f 1	"$FILE" | sort | uniq); do
		PREV_VERSION=
		PREV_INDEX=
		PREV_NIXPKGS_REV=
		while read -r ATTRNAME2 VERSION INDEX NIXPKGS_REV; do
			if [[ -n "$PREV_VERSION" ]]; then
				echo "$ATTRNAME $PREV_VERSION $PREV_INDEX $PREV_NIXPKGS_REV $INDEX $NIXPKGS_REV" >> "$VERSION_RANGES_DIR"/$PNAME
			fi
			PREV_VERSION=$VERSION
			PREV_INDEX=$INDEX
			PREV_NIXPKGS_REV=$NIXPKGS_REV
		done < <(grep "^$ATTRNAME " "$FILE")
		echo "$ATTRNAME $PREV_VERSION $PREV_INDEX $PREV_NIXPKGS_REV $FINAL_INDEX $FINAL_NIXPKGS_REV" >> "$VERSION_RANGES_DIR"/$PNAME
	done
	# sort by last nixpkgs index
	sort -k 5 "$VERSION_RANGES_DIR"/$PNAME -o "$VERSION_RANGES_DIR"/$PNAME
done

for FILE in "$VERSION_RANGES_DIR"/*; do
	echo "$FILE"
	PNAME=$(basename -- "$FILE")

	while read -r ATTRNAME VERSION FIRST_INDEX FIRST_NIXPKGS_REV LAST_INDEX LAST_NIXPKGS_REV; do
		DIR_PATH="packages/$PNAME/${PNAME}.${VERSION}"
		mkdir -p "$DIR_PATH"
		FILE_PATH="$DIR_PATH/opam"
		FILE_CONTENT=$(cat <<EOF
opam-version: "2.0"
depends: [
  "nixpkgs" {>= "$FIRST_INDEX" & < "$LAST_INDEX" }
]
depexts: [
  "$ATTRNAME"
]
EOF
		)
		echo "$FILE_CONTENT" > "$FILE_PATH"

		DIR_PATH="packages/nixpkgs/nixpkgs.${FIRST_INDEX}"
		mkdir -p "$DIR_PATH"
		FILE_PATH="$DIR_PATH/opam"
		FILE_CONTENT=$(cat <<EOF
opam-version: "2.0"
conflict-class: "nixpkgs"
x-nixpkgs-hash: "$FIRST_NIXPKGS_REV"
EOF
		)
		echo "$FILE_CONTENT" > "$FILE_PATH"

		DIR_PATH="packages/nixpkgs/nixpkgs.${LAST_INDEX}"
		mkdir -p "$DIR_PATH"
		FILE_PATH="$DIR_PATH/opam"
		FILE_CONTENT=$(cat <<EOF
opam-version: "2.0"
conflict-class: "nixpkgs"
x-nixpkgs-hash: "$LAST_NIXPKGS_REV"
EOF
		)
		echo "$FILE_CONTENT" > "$FILE_PATH"
	done < "$FILE"
done
