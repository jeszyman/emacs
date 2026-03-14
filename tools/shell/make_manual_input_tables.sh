#!/usr/bin/env bash
# ============================================================
# AUTO-GENERATED — DO NOT EDIT DIRECTLY
# Edits will be overwritten on next org-babel tangle.
# 
# Source:  /home/jeszyman/repos/emacs/emacs.org
# Author:  Jeffrey Szymanski
# Tangled: 2026-03-14 14:18:19
# ============================================================


# Script variables

org_file="${1}"
table_suffix="${2:-manualInputTable}"
out_dir="${3:-/tmp}"
org_tsv_exporter="${4:-~/repos/basecamp/tools/lisp/org_tsv_export.el}"
org_exc="${5:-/usr/local/bin/emacs}"

tables_array=()
mapfile -t tables_array < <(cat $org_file |
                                egrep $table_suffix |
                                sed 's/^.*\ //g')

for table in "${tables_array[@]}";
do
    $org_exc --batch $org_file -l $org_tsv_exporter --eval '(my-tbl-export "'"$table"'" "'"$out_dir"'")'
done
