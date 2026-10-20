using Godot;
using System;
using System.Runtime.CompilerServices;

public partial class Roomba : CharacterBody3D
{
	public const float Speed = 1.0f;


	public float location_delay = 0.0f;

	[Export]
	public NavigationAgent3D nav;
	

	public override void _PhysicsProcess(double delta)
	{

		location_delay -= 0.01f;

		if (location_delay <= 0 & nav.IsNavigationFinished())
		{
			Vector3 pos = new Vector3(0f,0f,0f);
			pos += new Vector3(GD.RandRange(-30,30),GD.RandRange(-5,5),GD.RandRange(-30,30));
			pos.Y = 0f;
			nav.TargetPosition = pos;
			Vector3 look_pos = new Vector3(0,0,0);
			location_delay = 5.0f;
		}
			
		
		Vector3 dir = GlobalPosition.DirectionTo(nav.TargetPosition);
		dir.Y = 0f;


			

		// Add the gravity.

		Velocity = dir * Speed;


		if (!IsOnFloor())
		{
			Velocity += GetGravity() * (float)delta;
		}

		if  (nav.IsNavigationFinished())
		{
			Velocity = new Vector3(0,0,0);
		}


		MoveAndSlide();
	}
}
