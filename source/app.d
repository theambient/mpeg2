
import std.stdio;
import std.exception;
import decoder;

class App
{
	void run(string[] args)
	{
		enforce(args.length == 3, "usage: <input-file> <output-file>");

		string input_file = args[1];
		string output_file = args[2];

		auto decoder = new Decoder(input_file);

		int cnt = 0;
		for(Frame f = decoder.decode(); f !is null; f = decoder.decode())
		{
			writefln("decoded pic #%d", cnt);
			++cnt;
		}
	}
}

void main(string[] args)
{
	auto app = new App;
	app.run(args);
}
