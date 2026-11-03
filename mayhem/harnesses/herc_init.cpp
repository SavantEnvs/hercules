// Shared bring-up for the Hercules fuzz harnesses: pulls in the core translation unit (with its
// main() renamed) so the file-static core_defaults() can run, then initialises just the common
// interfaces the harnesses touch.
#define HERCULES_CORE
#define main hercules_core_main
#include "common/core.cpp"
#undef main

int do_init(int argc, char **argv) { return 0; }
int do_final(void) { return 0; }
void do_abort(void) { }
void set_server_type(void) { SERVER_TYPE = SERVER_TYPE_UNKNOWN; }
void cmdline_args_init_local(void) { }

extern "C" void herc_fuzz_init(void)
{
	static bool done = false;
	if (done) {
		return;
	}
	done = true;
	core->arg_c = 0;
	core->arg_v = NULL;
	core->runflag = CORE_ST_RUN;
	core_defaults();
	iMalloc->init();
	showmsg->init();
	showmsg->silent = 0xff;
	nullpo->init();
}
