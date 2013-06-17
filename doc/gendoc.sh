#!/bin/sh
COQ2HTML=$COQEAL/../coq2html
make -C makeDot
make -C $COQ2HTML
cd $COQEAL/doc
globs=`ls ../*.glob`
for i in `ls ../*.v`
do
  $COQ2HTML/coq2html -o %.html $globs $i
done
cd $COQEAL
$COQBIN/coqdep -noglob -I . -R $SSRLIB Ssreflect *.v > depend
#sed s/[[:space:]][[:alnum:]]*.v.beautified//g depend > doc/depend
cd $COQEAL/doc
$WORKSPACE/makeDot/makedot depend
dot -Tpng -o depend.png -Tcmapx -o depend.map depend.dot
dot -Tsvg -o depend.svg depend.dot
cat toc.html.head depend.map toc.html.tail > toc.html
#cp *.html depend.* /net/servers/www-sop/members/Maxime.Denes/coqeal
