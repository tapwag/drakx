#define _GNU_SOURCE
#include <stdlib.h>
#include <stdio.h>
#include "dietfeatures.h"
#include <errno.h>
#include "dietwarning.h"

ssize_t getdelim(char **lineptr, size_t *n, int delim, FILE *stream) {
  size_t i;
  if (!lineptr || !n) {
    errno=EINVAL;
    return -1;
  }
  if (!*lineptr) *n=0;
  for (i=0; ; ) {
    int x=fgetc(stream);
    if (i>=*n) {
      int tmp=*n+100;
      char* new=realloc(*lineptr,tmp);
      if (!new) return -1;
      *lineptr=new; *n=tmp;
    }
    if (x==EOF) { (*lineptr)[i]=0; return -1; }
    (*lineptr)[i]=x;
    ++i;
    if (x==delim) break;
  }
  (*lineptr)[i]=0;
  return i;
}

link_warning("getdelim","warning: portable software should not use getdelim!")
