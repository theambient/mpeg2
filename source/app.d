
import darg;
import std.stdio;
import std.exception;
import decoder;

struct Options
{
	@Option("help", "h")
	@Help("Prints this help.")
	OptionFlag help;

	@Option("frames", "f")
	@Help("Number of frames to decode.")
	size_t frames_to_decode = size_t.max;

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
		for(Frame f = decoder.decode(); f !is null && cnt < options.frames_to_decode; f = decoder.decode())
		{
			writefln("decoded pic #%d", cnt);
			dump_frame(f);
			++cnt;
		}

		writefln("decoded %d frames", cnt);
	}

	void dump_frame(Frame f)
	{
		auto buf = new ubyte[f.width*f.height + f.width*f.height / 2];
		for(size_t i=0; i<f.width*f.height; ++i)
		{
			buf[i] = cast(ubyte)f.planes[0][i % f.width, i / f.width];
		}

		foreach(cc; 1..3)
		{
			auto base = f.width*f.height + (cc == 1?0:f.width*f.height / 4);

			for(size_t i=0; i<f.height / 2; ++i)
			{
				for(size_t j=0; j<f.width / 2; ++j)
				{
					auto v = (0L
						+ f.planes[cc][2*j, 2*i]
						+ f.planes[cc][2*j + 1, 2*i]
						+ f.planes[cc][2*j, 2*i + 1]
						+ f.planes[cc][2*j + 1, 2*i + 1]
						) / 4;

					buf[base + i * f.width / 2 + j] = cast(ubyte) v;
				}
			}
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
