#include <exec/execbase.h>
#include <dos/dos.h>
#include <proto/exec.h>

extern struct ExecBase *SysBase;
const char* VERSION = "$VER: femustart 0.1";

#ifndef AFB_68060
#define AFB_68060 7
#endif
#ifndef AFB_68080
#define AFB_68080 10
#endif
#ifndef AFF_68060
#define AFF_68060 (1<<AFB_68060)
#endif
#ifndef AFF_68080
#define AFF_68080 (1<<AFB_68080)
#endif

int main() {
	struct Library *DOSBase = NULL;
	char cmd[256]; 
	
	/* Open dos.library */
	if (!(DOSBase = OpenLibrary(DOSNAME, 33))) {
		printf("Unable to open %s\n", DOSNAME);
		return 0;
	}
	
	/* Launch femu */
	if (SysBase->AttnFlags & AFF_68080) {
		snprintf(cmd, 256, "femu.080");
		Execute(cmd, NULL, NULL);
	} else if (SysBase->AttnFlags & AFF_68040) {
		snprintf(cmd, 256, "femu.040");
		Execute(cmd, NULL, NULL);
	} else if (SysBase->AttnFlags & AFF_68020) {
		snprintf(cmd, 256, "femu.020");
		Execute(cmd, NULL, NULL);
	} else {
		printf("Unsupported CPU!\n");
	}
	
	/* Close dos.library */
	CloseLibrary(DOSBase);	
}