#/bin/bash


DATA_FILE=$1

if [ "$DATA_FILE" = "" ] ; then
  echo "Specify a test file (1st arg)"
  exit 1
fi

if [ ! -f "$DATA_FILE" ] ; then
  echo "The following data file doesn't exist: $DATA_FILE"
  exit 1
fi

SPACE=$2

if [ "$SPACE" = "" ] ; then
  echo "Specify the space (2d arg)"
  exit 1
fi

THREAD_QTY=$3

if [ "$THREAD_QTY" = "" ] ; then
  echo "Specify the number of test threads (3d arg)"
  exit 1
fi

# If you have python, latex, and PGF installed, 
# you can set the following variable to 1 to generate a performance plot.
GEN_PLOT=$3
if [ "$GEN_PLOT" = "" ] ; then
  echo "Specify a plot-generation flag: 1 to generate plots (3d arg)"
  exit 1
fi

TEST_SET_QTY=2
QUERY_QTY=500
RESULT_FILE=output_file
K=10
LOG_FILE_PREFIX="log_$K"
BIN_DIR="../similarity_search"
GS_CACHE_DIR="gs_cache"
mkdir -p $GS_CACHE_DIR
CACHE_PREFIX_GS=$GS_CACHE_DIR/test_run.tq=$THREAD_QTY

rm -f $RESULT_FILE.*
rm -f $LOG_FILE_PREFIX.*
rm -f $CACHE_PREFIX_GS*

COMMON_ARGS="-s $SPACE -i $DATA_FILE -g $CACHE_PREFIX_GS -b $TEST_SET_QTY -Q  $QUERY_QTY -k $K  --outFilePrefix $RESULT_FILE --threadTestQty $THREAD_QTY "

LN=1

function do_run {
  DO_APPEND="$1"
  if [ "$DO_APPEND" = "" ] ; then
    echo "Specify DO_APPEND (1st arg of the function do_run)"
    exit 1
  fi
  if [ "$DO_APPEND" = "1" ] ; then
    APPEND_FLAG=" -a "
  fi
  METHOD_NAME="$2"
  if [ "$METHOD_NAME" = "" ] ; then
    echo "Specify METHOD_NAME (2d arg of the function do_run)"
    exit 1
  fi
  INDEX_ARGS="$3"
  if [ "$INDEX_ARGS" = "" ] ; then
    echo "Specify INDEX_ARGS (3d arg of the function do_run)"
    exit 1
  fi
  QUERY_ARGS="$4"
  INDEX_NAME="$5"

  if [ "$INDEX_NAME" = "" ] ; then
    cmd="$BIN_DIR/release/experiment $COMMON_ARGS -m "$METHOD_NAME" $INDEX_ARGS $QUERY_ARGS $APPEND_FLAG -l ${LOG_FILE_PREFIX}.$LN"
    echo "$cmd"
    bash -c "$cmd"
    if [ "$?" != "0" ] ; then
      echo "Failure!"
      exit 1 
    fi
  else
    # Indices are to be deleted manually!
    rm -f ${INDEX_NAME}*

    cmd="$BIN_DIR/release/experiment $COMMON_ARGS -S "$INDEX_NAME" -m "$METHOD_NAME" $INDEX_ARGS $APPEND_FLAG -l ${LOG_FILE_PREFIX}_index.$LN"
    echo "$cmd"
    bash -c "$cmd"
    if [ "$?" != "0" ] ; then
      echo "Failure!"
      exit 1 
    fi

    cmd="$BIN_DIR/release/experiment $COMMON_ARGS -L "$INDEX_NAME" -m "$METHOD_NAME" $QUERY_ARGS $APPEND_FLAG -l ${LOG_FILE_PREFIX}_query.$LN"
    echo "$cmd"
    bash -c "$cmd"
    if [ "$?" != "0" ] ; then
      echo "Failure!"
      exit 1 
    fi
  fi
  LN=$((LN+1))
}

# Methods that may create an index (at least for some spaces)
do_run 0 "napp" " -c numPivot=512,numPivotIndex=64 " "-t numPivotSearch=40 -t numPivotSearch=42 -t numPivotSearch=44 -t numPivotSearch=46 -t numPivotSearch=48" "napp.index"
do_run 1 "sw-graph" " -c NN=10 " " -t efSearch=10 -t efSearch=20 -t efSearch=40 -t efSearch=80 -t efSearch=160 -t efSearch=240" "sw-graph.index"
if [ "$SPACE" = "l2" -o "$SPACE" = "cosinesimil" ] ; then 
  do_run 1 "hnsw"     " -c M=10 "  " -t efSearch=10 -t efSearch=20 -t efSearch=40 -t efSearch=80 -t efSearch=160 -t efSearch=240" "hnsw.index"
else
  do_run 1 "hnsw"     " -c M=10 "  " -t efSearch=10 -t efSearch=20 -t efSearch=40 -t efSearch=80 -t efSearch=160 -t efSearch=240" 
fi

# Methods that do not support creation of an index
do_run 1 "vptree" " -c tuneK=$K,bucketSize=50,desiredRecall=0.99,chunkBucket=1 " ""
do_run 1 "vptree" " -c tuneK=$K,bucketSize=50,desiredRecall=0.975,chunkBucket=1 " ""
do_run 1 "vptree" " -c tuneK=$K,bucketSize=50,desiredRecall=0.95,chunkBucket=1 " ""
do_run 1 "vptree" " -c tuneK=$K,bucketSize=50,desiredRecall=0.925,chunkBucket=1 " ""
do_run 1 "vptree" " -c tuneK=$K,bucketSize=50,desiredRecall=0.9,chunkBucket=1 " ""

if [ "$GEN_PLOT" = 1 ] ; then
  ./genplot_configurable.py -i ${RESULT_FILE}_K=${K}.dat -o plot_${K}_NN -x 1~norm~Recall -y 1~log~ImprEfficiency -l "1~south west" -t "Improvement in efficiency vs recall" -n "MethodName" -a axis_desc.txt -m meth_desc.txt
fi
