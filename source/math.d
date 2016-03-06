
module math;

byte sign(T)(T v)
{
	if(v<0) return -1;
	else if(v > 0) return 1;
	else return 0;
}

T saturate(T, T min, T max)(T v)
{
	if(v < min) v = min;
	if(v > max) v = max;

	return v;
}
