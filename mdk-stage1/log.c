/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <errno.h>

#include "log.h"

static FILE * logfile = NULL;

void vlog_message_nobs(const char * s, va_list args)
{
	fprintf(logfile, "* ");
	vfprintf(logfile, s, args);
}

void vlog_message(const char * s, va_list args)
{
	vlog_message_nobs(s, args);
	fprintf(logfile, "\n");
	fflush(logfile);
}


void log_message(const char * s, ...)
{
	va_list args;

	if (!logfile) {
		fprintf(stderr, "Log is not open!\n");
		return;
	}

	va_start(args, s);
	vlog_message(s, args);
	va_end(args);
	
	return;
}

void log_perror(char *msg)
{
	log_message("%s %s", strerror(errno), msg);
}


void open_log(int testing)
{
	if (!testing) {
		logfile = fopen("/dev/tty3", "w");
		if (!logfile)
			logfile = fopen("/tmp/install.log", "a");
	}
	else
		logfile = fopen("debug.log", "w");
}

void close_log(void)
{
	if (logfile)
		fclose(logfile);
}
