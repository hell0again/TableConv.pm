#!/bin/sh
SCRIPT_DIR=$(cd $(dirname $0); pwd)
cd ${SCRIPT_DIR}/../..
tableconv convert < ${SCRIPT_DIR}/source.csv | tableconv reverse --ff=unix > ${SCRIPT_DIR}/out.csv
#carton exec perl -d -Ilib ./script/tableconv conv ${SCRIPT_DIR}/source.csv > ${SCRIPT_DIR}/conv.xlsx
#carton exec perl -d -Ilib ./script/tableconv reverse --ff=unix ${SCRIPT_DIR}/conv.xlsx > ${SCRIPT_DIR}/out.csv
diff -u ${SCRIPT_DIR}/{source,out}.csv

