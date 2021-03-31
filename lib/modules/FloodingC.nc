

configuration FloodingC{
	provides interface Flooding;
}
Implementation {
	components FloodingP;
	Flooding = FloodingP.Flooding;
}