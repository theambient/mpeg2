
module math;

import std.math;

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

real norm(V,U)(V[] v, U[] u)
{
	real sum = 0;
	for(size_t i=0; i<v.length; ++i)
	{
		auto t = v[i] - u[i];
		sum += t*t;
	}

	return sqrt(sum) / v.length;
}

real norm(V)(V[] v)
{
	real sum = 0;
	for(size_t i=0; i<v.length; ++i)
	{
		sum += v[i] * v[i];
	}

	return sum;
}
