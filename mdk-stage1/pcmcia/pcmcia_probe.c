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

/* Code comes from /anonymous@projects.sourceforge.net:/pub/pcmcia-cs/pcmcia-cs-3.1.23.tar.bz2
 *
 *   Licence of this code follows:

    PCMCIA controller probe

    probe.c 1.52 2000/06/12 21:33:02

    The contents of this file are subject to the Mozilla Public
    License Version 1.1 (the "License"); you may not use this file
    except in compliance with the License. You may obtain a copy of
    the License at http://www.mozilla.org/MPL/

    Software distributed under the License is distributed on an "AS
    IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
    implied. See the License for the specific language governing
    rights and limitations under the License.

    The initial developer of the original code is David A. Hinds
    <dahinds@users.sourceforge.net>.  Portions created by David A. Hinds
    are Copyright (C) 1999 David A. Hinds.  All Rights Reserved.

    Alternatively, the contents of this file may be used under the
    terms of the GNU Public License version 2 (the "GPL"), in which
    case the provisions of the GPL are applicable instead of the
    above.  If you wish to allow the use of your version of this file
    only under the terms of the GPL and not to allow others to use
    your version of this file under the MPL, indicate your decision
    by deleting the provisions above and replace them with the notice
    and other provisions required by the GPL.  If you do not delete
    the provisions above, a recipient may use your version of this
    file under either the MPL or the GPL.
    
======================================================================*/

#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>

#include "log.h"
#include "pcmcia.h"

/*====================================================================*/

typedef struct {
	u_short	vendor, device;
	char	*tag;
	char	*name;
} pci_id_t;

pci_id_t pci_id[] = {
	{ 0x1013, 0x1100, "Cirrus Logic CL 6729", "Cirrus PD6729" },
	{ 0x1013, 0x1110, "Cirrus Logic PD 6832", "Cirrus PD6832" },
	{ 0x10b3, 0xb106, "SMC 34C90", "SMC 34C90" },
	{ 0x1180, 0x0465, "Ricoh RL5C465", "Ricoh RL5C465" },
	{ 0x1180, 0x0466, "Ricoh RL5C466", "Ricoh RL5C466" },
	{ 0x1180, 0x0475, "Ricoh RL5C475", "Ricoh RL5C475" },
	{ 0x1180, 0x0476, "Ricoh RL5C476", "Ricoh RL5C476" },
	{ 0x1180, 0x0478, "Ricoh RL5C478", "Ricoh RL5C478" },
	{ 0x104c, 0xac12, "Texas Instruments PCI1130", "TI 1130" },
	{ 0x104c, 0xac13, "Texas Instruments PCI1031", "TI 1031" },
	{ 0x104c, 0xac15, "Texas Instruments PCI1131", "TI 1131" },
	{ 0x104c, 0xac16, "Texas Instruments PCI1250", "TI 1250A" },
	{ 0x104c, 0xac17, "Texas Instruments PCI1220", "TI 1220" },
	{ 0x104c, 0xac19, "Texas Instruments PCI1221", "TI 1221" },
	{ 0x104c, 0xac1a, "Texas Instruments PCI1210", "TI 1210" },
	{ 0x104c, 0xac1d, "Texas Instruments PCI1251A", "TI 1251A" },
	{ 0x104c, 0xac1f, "Texas Instruments PCI1251B", "TI 1251B" },
	{ 0x104c, 0xac1b, "Texas Instruments PCI1450", "TI 1450" },
	{ 0x104c, 0xac1c, "Texas Instruments PCI1225", "TI 1225" },
	{ 0x104c, 0xac1e, "Texas Instruments PCI1211", "TI 1211" },
	{ 0x104c, 0xac50, "Texas Instruments PCI1410", "TI 1410" },
	{ 0x104c, 0xac51, "Texas Instruments PCI1420", "TI 1420" },
	{ 0x1217, 0x6729, "O2 Micro 6729", "O2Micro OZ6729" },
	{ 0x1217, 0x673a, "O2 Micro 6730", "O2Micro OZ6730" },
	{ 0x1217, 0x6832, "O2 Micro 6832/6833", "O2Micro OZ6832/OZ6833" },
	{ 0x1217, 0x6836, "O2 Micro 6836/6860", "O2Micro OZ6836/OZ6860" },
	{ 0x1217, 0x6872, "O2 Micro 6812", "O2Micro OZ6812" },
	{ 0x1179, 0x0603, "Toshiba ToPIC95-A", "Toshiba ToPIC95-A" },
	{ 0x1179, 0x060a, "Toshiba ToPIC95-B", "Toshiba ToPIC95-B" },
	{ 0x1179, 0x060f, "Toshiba ToPIC97", "Toshiba ToPIC97" },
	{ 0x1179, 0x0617, "Toshiba ToPIC100", "Toshiba ToPIC100" },
	{ 0x119b, 0x1221, "Omega Micro 82C092G", "Omega Micro 82C092G" },
	{ 0x8086, 0x1221, "Intel 82092AA", "Intel 82092AA" }
};
#define PCI_COUNT (sizeof(pci_id)/sizeof(pci_id_t))

static int pci_probe(void)
{
	char s[256], *name = NULL;
	u_int device, vendor, i;
	FILE *f;
    
	log_message("PCMCIA: probing PCI bus..");

	f = fopen("/proc/bus/pci/devices", "r");

	if (!f) {
		log_message("where are you going without /proc/bus/pci/devices ??");
		return -1;
	}

	while (fgets(s, 256, f) != NULL) {
		u_int n = strtoul(s+5, NULL, 16);
		vendor = (n >> 16); device = (n & 0xffff);
		for (i = 0; i < PCI_COUNT; i++)
			if ((vendor == pci_id[i].vendor) &&
			    (device == pci_id[i].device)) break;
		if (i < PCI_COUNT) {
			name = pci_id[i].name;
			break;
		}
	}

	fclose(f);
    
	if (name) {
		log_message("\t%s found, 2 sockets.", name);
		return 0;
	} else {
		log_message("\tnot found.");
		return -ENODEV;
	}
}

/*====================================================================*/

#include <sys/io.h>
typedef u_short ioaddr_t;

#include "i82365.h"
#include "cirrus.h"
#include "vg468.h"

static ioaddr_t i365_base = 0x03e0;

static u_char i365_get(u_short sock, u_short reg)
{
	u_char val = I365_REG(sock, reg);
	outb(val, i365_base); val = inb(i365_base+1);
	return val;
}

static void i365_set(u_short sock, u_short reg, u_char data)
{
	u_char val = I365_REG(sock, reg);
	outb(val, i365_base); outb(data, i365_base+1);
}

static void i365_bset(u_short sock, u_short reg, u_char mask)
{
	u_char d = i365_get(sock, reg);
	d |= mask;
	i365_set(sock, reg, d);
}

static void i365_bclr(u_short sock, u_short reg, u_char mask)
{
	u_char d = i365_get(sock, reg);
	d &= ~mask;
	i365_set(sock, reg, d);
}

static int i365_probe(void)
{
	int val, sock, done;
	char *name = "i82365sl";

	log_message("PCMCIA: probing for Intel PCIC (ISA)..");
    
	sock = done = 0;
	ioperm(i365_base, 4, 1);
	ioperm(0x80, 1, 1);
	for (; sock < 2; sock++) {
		val = i365_get(sock, I365_IDENT);
		switch (val) {
		case 0x82:
			name = "i82365sl A step";
			break;
		case 0x83:
			name = "i82365sl B step";
			break;
		case 0x84:
			name = "VLSI 82C146";
			break;
		case 0x88: case 0x89: case 0x8a:
			name = "IBM Clone";
			break;
		case 0x8b: case 0x8c:
			break;
		default:
			done = 1;
		}
		if (done) break;
	}

	if (sock == 0) {
		log_message("\tnot found.");
		return -ENODEV;
	}

	if ((sock == 2) && (strcmp(name, "VLSI 82C146") == 0))
		name = "i82365sl DF";

	/* Check for Vadem chips */
	outb(0x0e, i365_base);
	outb(0x37, i365_base);
	i365_bset(0, VG468_MISC, VG468_MISC_VADEMREV);
	val = i365_get(0, I365_IDENT);
	if (val & I365_IDENT_VADEM) {
		if ((val & 7) < 4)
			name = "Vadem VG-468";
		else
			name = "Vadem VG-469";
		i365_bclr(0, VG468_MISC, VG468_MISC_VADEMREV);
	}
    
	/* Check for Cirrus CL-PD67xx chips */
	i365_set(0, PD67_CHIP_INFO, 0);
	val = i365_get(0, PD67_CHIP_INFO);
	if ((val & PD67_INFO_CHIP_ID) == PD67_INFO_CHIP_ID) {
		val = i365_get(0, PD67_CHIP_INFO);
		if ((val & PD67_INFO_CHIP_ID) == 0) {
			if (val & PD67_INFO_SLOTS)
				name = "Cirrus CL-PD672x";
			else {
				name = "Cirrus CL-PD6710";
				sock = 1;
			}
			i365_set(0, PD67_EXT_INDEX, 0xe5);
			if (i365_get(0, PD67_EXT_INDEX) != 0xe5)
				name = "VIA VT83C469";
		}
	}

	log_message("\t%s found, %d sockets.", name, sock);
	return 0;
    
} /* i365_probe */


/*====================================================================*/

#include "tcic.h"

static u_char tcic_getb(ioaddr_t base, u_char reg)
{
	u_char val = inb(base+reg);
	return val;
}

static void tcic_setb(ioaddr_t base, u_char reg, u_char data)
{
	outb(data, base+reg);
}

static u_short tcic_getw(ioaddr_t base, u_char reg)
{
	u_short val = inw(base+reg);
	return val;
}

static void tcic_setw(ioaddr_t base, u_char reg, u_short data)
{
	outw(data, base+reg);
}

static u_short tcic_aux_getw(ioaddr_t base, u_short reg)
{
	u_char mode = (tcic_getb(base, TCIC_MODE) & TCIC_MODE_PGMMASK) | reg;
	tcic_setb(base, TCIC_MODE, mode);
	return tcic_getw(base, TCIC_AUX);
}

static void tcic_aux_setw(ioaddr_t base, u_short reg, u_short data)
{
	u_char mode = (tcic_getb(base, TCIC_MODE) & TCIC_MODE_PGMMASK) | reg;
	tcic_setb(base, TCIC_MODE, mode);
	tcic_setw(base, TCIC_AUX, data);
}

static int get_tcic_id(ioaddr_t base)
{
	u_short id;
	tcic_aux_setw(base, TCIC_AUX_TEST, TCIC_TEST_DIAG);
	id = tcic_aux_getw(base, TCIC_AUX_ILOCK);
	id = (id & TCIC_ILOCKTEST_ID_MASK) >> TCIC_ILOCKTEST_ID_SH;
	tcic_aux_setw(base, TCIC_AUX_TEST, 0);
	return id;
}

static int tcic_probe_at(ioaddr_t base)
{
	int i;
	u_short old;
    
	/* Anything there?? */
	for (i = 0; i < 0x10; i += 2)
		if (tcic_getw(base, i) == 0xffff)
			return -1;

	log_message("\tat %#3.3x: ", base);

	/* Try to reset the chip */
	tcic_setw(base, TCIC_SCTRL, TCIC_SCTRL_RESET);
	tcic_setw(base, TCIC_SCTRL, 0);
    
	/* Can we set the addr register? */
	old = tcic_getw(base, TCIC_ADDR);
	tcic_setw(base, TCIC_ADDR, 0);
	if (tcic_getw(base, TCIC_ADDR) != 0) {
		tcic_setw(base, TCIC_ADDR, old);
		return -2;
	}
    
	tcic_setw(base, TCIC_ADDR, 0xc3a5);
	if (tcic_getw(base, TCIC_ADDR) != 0xc3a5)
		return -3;

	return 2;
}

static int tcic_probe(void)
{
	int sock, id;

	log_message("PCMCIA: probing for Databook TCIC-2 (ISA)..");
    
	ioperm(TCIC_BASE, 16, 1);
	ioperm(0x80, 1, 1);
	sock = tcic_probe_at(TCIC_BASE);
    
	if (sock <= 0) {
		log_message("\tnot found.");
		return -ENODEV;
	}

	id = get_tcic_id(TCIC_BASE);
	switch (id) {
	case TCIC_ID_DB86082:
		log_message("DB86082"); break;
	case TCIC_ID_DB86082A:
		log_message("DB86082A"); break;
	case TCIC_ID_DB86084:
		log_message("DB86084"); break;
	case TCIC_ID_DB86084A:
		log_message("DB86084A"); break;
	case TCIC_ID_DB86072:
		log_message("DB86072"); break;
	case TCIC_ID_DB86184:
		log_message("DB86184"); break;
	case TCIC_ID_DB86082B:
		log_message("DB86082B"); break;
	default:
		log_message("Unknown TCIC-2 ID 0x%02x", id);
	}
	log_message("\tfound at %#6x, %d sockets.\n", TCIC_BASE, sock);

	return 0;
    
} /* tcic_probe */


/*====================================================================*/

char * pcmcia_probe(void)
{
	if (!pci_probe())
		return "i82365";
	else if (!i365_probe())
		return "i82365";
	else if (!tcic_probe())
		return "tcic";
	else
		return NULL;
}
