
import darg;
import std.stdio;
import std.exception;
import decoder;

struct Options
{
	@Option("help", "h")
	@Help("Prints this help.")
	OptionFlag help;

	@Option("pictures", "p")
	@Help("Number of pictures to decode.")
	size_t pics_to_decode = size_t.max;

	@Argument("<input-file>")
	@Help("Input file")
	string input_file;

	@Argument("<output-file>")
	@Help("Output file")
	string output_file;
}

class App
{
	void run(string[] args)
	{
		auto options = parseArgs!Options(args[1..$]);

		out_fd = File(options.output_file, "wb");

		auto decoder = new Decoder(options.input_file);

		int cnt = 0;
		for(Picture p = decoder.decode(); p !is null && cnt < options.pics_to_decode; p = decoder.decode())
		{
			writefln("decoded pic #%d", cnt);
			dump_picture(p);
			++cnt;
			if(cnt == options.pics_to_decode) break; // to avoid one extra Picture decoding
		}

		writefln("decoded %d frames", cnt);
	}

	void dump_picture(Picture p)
	{
		auto buf = new ubyte[p.width*p.height + p.width*p.height / 2];

		uint dc = 0;
		foreach(cc; 0..3)
		{
			auto pixs = p.planes[cc].pixels;

			for(size_t i=0; i<pixs.length; ++i)
			{
				buf[dc + i] = cast(ubyte) pixs[i];
			}
			dc += pixs.length;
		}

		out_fd.rawWrite(buf);
	}

	private File out_fd;
}

int main(string[] args)
{
	immutable usage = usageString!Options("example");
	immutable help = helpString!Options;

	try
	{
		auto app = new App;
		app.run(args);
		return 0;
	}
	catch (ArgParseError e)
	{
		writeln(e.msg);
		writeln(usage);
		return 1;
	}
	catch (ArgParseHelp e)
	{
		// Help was requested
		writeln(usage);
		write(help);
		return 0;
	}
}
