#!/bin/bash
# Copyright Johns Hopkins University (Author: Daniel Povey) 2012.  Apache 2.0.

# begin configuration section.
cmd=run.pl
stage=0
min_lmwt=5
max_lmwt=17
reverse=false
#end configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/score_sclite.sh [--cmd (run.pl|queue.pl...)] <data-dir> <lang-dir|graph-dir> <decode-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --stage (0|1|2)                 # start scoring script from part-way through."
  echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
  echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  echo "    --reverse (true/false)          # score with time reversed features "
  exit 1;
fi

data=$1
lang=$2 # Note: may be graph directory not lang directory, but has the necessary stuff copied.
dir=$3

model=$dir/../final.mdl # assume model one level up from decoding dir.

hubscr=$KALDI_ROOT/tools/sctk/bin/hubscr.pl 
[ ! -f $hubscr ] && echo "Cannot find scoring program at $hubscr" && exit 1;
hubdir=`dirname $hubscr`

for f in $data/stm $data/glm $lang/words.txt $lang/phones/word_boundary.int \
     $model $data/segments $data/reco2file_and_channel $dir/lat.1.gz; do
  [ ! -f $f ] && echo "$0: expecting file $f to exist" && exit 1;
done

name=`basename $data`; # e.g. eval2000

mkdir -p $dir/scoring/log

if [ $stage -le 0 ]; then
  if $reverse; then
    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/get_ctm.LMWT.log \
      mkdir -p $dir/score_LMWT/ '&&' \
      lattice-1best --lm-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
      lattice-reverse ark:- ark:- \| \
      lattice-align-words --reorder=false $lang/phones/word_boundary.int $model ark:- ark:- \| \
      nbest-to-ctm ark:- - \| \
      utils/int2sym.pl -f 5 $lang/words.txt  \| \
      utils/convert_ctm.pl $data/segments $data/reco2file_and_channel \
      '>' $dir/score_LMWT/$name.ctm || exit 1;
  else
    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/get_ctm.LMWT.log \
      mkdir -p $dir/score_LMWT/ '&&' \
      lattice-1best --lm-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
      lattice-align-words $lang/phones/word_boundary.int $model ark:- ark:- \| \
      nbest-to-ctm ark:- - \| \
      utils/int2sym.pl -f 5 $lang/words.txt  \| \
      utils/convert_ctm.pl $data/segments $data/reco2file_and_channel \
      '>' $dir/score_LMWT/$name.ctm || exit 1;
  fi
fi

if [ $stage -le 1 ]; then
# Remove some stuff we don't want to score, from the ctm.
  for x in $dir/score_*/$name.ctm; do
    cp $x $dir/tmpf;
    cat $dir/tmpf | grep -i -v -E '\[NOISE|LAUGHTER|VOCALIZED-NOISE\]' | \
      grep -i -v -E '<UNK>' > $x;
#      grep -i -v -E '<UNK>|%HESITATION' > $x;  # hesitation is scored
  done
fi

# Score the set...
if [ $stage -le 2 ]; then  
  $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.LMWT.log \
    cp $data/stm $dir/score_LMWT/ '&&' \
    $hubscr -p $hubdir -V -l english -h hub5 -g $data/glm -r $dir/score_LMWT/stm $dir/score_LMWT/${name}.ctm || exit 1;
fi

### Scoring of subsets...
# For eval2000 score the subsets
if [ "$name" == "eval2000" ]; then
  # Score only the, swbd part...
  if [ $stage -le 3 ]; then  
    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.swbd.LMWT.log \
      grep -v '^en_' $data/stm '>' $dir/score_LMWT/stm.swbd '&&' \
      grep -v '^en_' $dir/score_LMWT/${name}.ctm '>' $dir/score_LMWT/${name}.ctm.swbd '&&' \
      $hubscr -p $hubdir -V -l english -h hub5 -g $data/glm -r $dir/score_LMWT/stm.swbd $dir/score_LMWT/${name}.ctm.swbd || exit 1;
  fi
  # Score only the, callhome part...
  if [ $stage -le 3 ]; then  
    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.callhm.LMWT.log \
      grep -v '^sw_' $data/stm '>' $dir/score_LMWT/stm.callhm '&&' \
      grep -v '^sw_' $dir/score_LMWT/${name}.ctm '>' $dir/score_LMWT/${name}.ctm.callhm '&&' \
      $hubscr -p $hubdir -V -l english -h hub5 -g $data/glm -r $dir/score_LMWT/stm.callhm $dir/score_LMWT/${name}.ctm.callhm || exit 1;
  fi
fi

# For eval2001 score the subsets
if [ "$name" == "eval2001" ]; then
  # Score only the, swbd part1...
  if [ $stage -le 3 ]; then  
    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.swb.LMWT.log \
      grep -e '"^sw4"' -e '"^;"' $data/stm '>' $dir/score_LMWT/stm.swb1 '&&' \
      grep -e '"^sw4"' $dir/score_LMWT/${name}.ctm '>' $dir/score_LMWT/${name}.ctm.swb1 '&&' \
      $hubscr -p $hubdir -V -l english -h hub5 -g $data/glm -r $dir/score_LMWT/stm.swb1 $dir/score_LMWT/${name}.ctm.swb1 || exit 1;
  fi
  if [ $stage -le 3 ]; then  
    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.swbd.LMWT.log \
      grep -e '"^971"' -e '"^;"' $data/stm '>' $dir/score_LMWT/stm.swb2p3 '&&' \
      grep -e '"^971"' $dir/score_LMWT/${name}.ctm '>' $dir/score_LMWT/${name}.ctm.swb2p3 '&&' \
      $hubscr -p $hubdir -V -l english -h hub5 -g $data/glm -r $dir/score_LMWT/stm.swb2p3 $dir/score_LMWT/${name}.ctm.swb2p3 || exit 1;
  fi
  if [ $stage -le 3 ]; then  
    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.swbd.LMWT.log \
      grep -e '"^sw_4"' -e '"^;"' $data/stm '>' $dir/score_LMWT/stm.swb2p4cell '&&' \
      grep -e '"^sw_4"' $dir/score_LMWT/${name}.ctm '>' $dir/score_LMWT/${name}.ctm.swb2p4cell '&&' \
      $hubscr -p $hubdir -V -l english -h hub5 -g $data/glm -r $dir/score_LMWT/stm.swb2p4cell $dir/score_LMWT/${name}.ctm.swb2p4cell || exit 1;
  fi
fi


exit 0
