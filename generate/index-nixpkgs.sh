#!/usr/bin/env bash

export NIXPKGS=/home/rtg24/nixpkgs
export TMPFS=/dev/shm/nixpkgs
export SPLITS_DIR=$TMPFS/revisions-split
export REVISIONS=$TMPFS/revisions
export WORKTREE_DIR=$TMPFS/worktree
export PERSIST_DIR=/mnt/nixpkgs-json
export CORES=256
mkdir -p $SPLITS_DIR $WORKTREE $PERSIST_DIR

# $CORES workers lauched for a segment of the Nixpkgs history
worker() {
	REVISION_FILE=$1
	PREV_JSON=
	while IFS= read -r ID; do
		INDEX=$(echo $ID | cut -d "-" -f 1)
		REV=$(echo $ID | cut -d "-" -f 2)
		JSON=${TMPFS}/${INDEX}_${REV}.json
		echo "$REVISION_FILE prev $PREV_JSON evaluating $JSON"

		git -C $NIXPKGS worktree add $WORKTREE_DIR/$ID $REV &> /dev/null || return 1
		nix-env -qaP --json -f $WORKTREE_DIR/$ID > $JSON 2> /dev/null
		EVAL_STATUS=$?
		git -C $NIXPKGS worktree remove $WORKTREE_DIR/$ID &> /dev/null || return 1
		if [ "$EVAL_STATUS" != "0" ]; then
			echo "$REVISION_FILE failed to eval $ID"
			rm $JSON
			continue
		fi

		if [ ! -z $PREV_JSON ]; then
			PERSIST_JSON=$PERSIST_DIR/${ID}_diff.json
			jq -n --slurpfile a $JSON --slurpfile b $PREV_JSON '
				def get_diff(x; y):
					reduce (x | keys_unsorted[]) as $key ({}; 
						if x[$key] != y[$key] then . + { ($key): x[$key] } else . end);
				get_diff($a[0]; $b[0])
			' > $PERSIST_JSON
			if [ "$(cat $PERSIST_JSON)" == "{}" ]; then
				echo "$REVISION_FILE diff $JSON $PREV_JSON empty"
				rm $PERSIST_JSON
			fi
			echo "$REVISION_FILE persisting diff $JSON $PREV_JSON as $PERSIST_JSON"
			rm $PREV_JSON
			PREV_JSON=$JSON
		# if this is the first revision
		else
			PERSIST_JSON=$PERSIST_DIR/$ID.json
			cp $JSON $PERSIST_JSON
			PREV_JSON=$JSON
		fi
	done < $REVISION_FILE
}
export -f worker

git -C $NIXPKGS rev-list HEAD --reverse --topo-order --no-merges | awk '{printf "%06d-%s\n", NR, $0}' > $REVISIONS
cat $REVISIONS | split -l $(( $(cat $REVISIONS | wc -l) / 256 )) -d - $SPLITS_DIR/
find $SPLITS_DIR | xargs -I {} -P $CORES bash -c "worker {}"
