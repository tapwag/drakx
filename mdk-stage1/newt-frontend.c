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


/*
 * Each different frontend must implement all functions defined in frontend.h
 */


#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include "stage1.h"
#include "log.h"
#include "newt.h"

#include "frontend.h"


void init_frontend(void)
{
	newtInit();
	newtCls();
	
	newtDrawRootText(0, 0, "Welcome to Linux-Mandrake (" VERSION ") " __DATE__ " " __TIME__);
	
	newtPushHelpLine("  <Tab>/<Alt-Tab> between elements, <Space>/<Enter> selects");
}


void finish_frontend(void)
{
	newtFinished();
}


void error_message(char *msg)
{
	newtWinMessage("Error", "Ok", msg);
}

void wait_message(char *msg, ...)
{
	int width = 36;
	int height = 3;
	char * title = "Please wait...";
	newtComponent t, f;
	char * buf = NULL;
	int size = 0;
	int i = 0;
	va_list args;
	
	va_start(args, msg);
	
	do {
		size += 1000;
		if (buf) free(buf);
		buf = malloc(size);
		i = vsnprintf(buf, size, msg, args);
	} while (i == size);
	
	va_end(args);
	
	newtCenteredWindow(width, height, title);

	t = newtTextbox(1, 1, width - 2, height - 2, NEWT_TEXTBOX_WRAP);
	newtTextboxSetText(t, buf);
	f = newtForm(NULL, NULL, 0);

	free(buf);

	newtFormAddComponent(f, t);

	newtDrawForm(f);
	newtRefresh();
	newtFormDestroy(f);
}

void remove_wait_message(void)
{
	newtPopWindow();
}


enum return_type ask_from_list_comments(char *msg, char ** elems, char ** elems_comments, char ** choice)
{
	char * items[50];
	int answer = 0, rc;
	char ** sav_elems = elems;
	int i;

	i = 0;
	while (elems && *elems) {
		items[i] = malloc(sizeof(char) * (strlen(*elems) + strlen(*elems_comments) + 3));
		strcpy(items[i], *elems);
		strcat(items[i], " (");
		strcat(items[i], *elems_comments);
		strcat(items[i], ")");
		i++;
		elems++;
		elems_comments++;
	}
	items[i] = NULL;

	rc = newtWinMenu("Please choose...", msg, 52, 5, 5, 7, items, &answer, "Ok", "Cancel", NULL);

	if (rc == 2)
		return RETURN_BACK;

	*choice = strdup(sav_elems[answer]);

	return RETURN_OK;
}


enum return_type ask_from_list(char *msg, char ** elems, char ** choice)
{
	int answer = 0, rc;

	rc = newtWinMenu("Please choose...", msg, 52, 5, 5, 7, elems, &answer, "Ok", "Cancel", NULL);

	if (rc == 2)
		return RETURN_BACK;

	*choice = strdup(elems[answer]);

	return RETURN_OK;
}


enum return_type ask_yes_no(char *msg)
{
	int rc;

	rc = newtWinTernary("Please answer..", "Yes", "No", "Back", msg);

	if (rc == 1)
		return RETURN_OK;
	else if (rc == 3)
		return RETURN_BACK;
	else return RETURN_ERROR;
}
