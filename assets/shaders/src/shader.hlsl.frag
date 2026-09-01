struct Input {
	float4 color : TEXTCOORD0;
	float2 uv : TEXTCOORD1;
};

Texture2D<float4> tex : register(t0, space2);
SamplerState smp : register(s0, space2);

float4 main(Input input) : SV_Target0 {
	return tex.Sample(smp, input.uv) * input.color;
}