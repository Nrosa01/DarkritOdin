cbuffer UBO : register(b0, space1) {
	float4x4 mvp;
}

struct Input {
	float3 position : TEXTCOORD0;
	float4 color : TEXTCOORD1;
	float2 uv : TEXTCOORD2;
};

struct Output {
	float4 position : SV_POSITION;
	float4 color : TEXTCOORD0;
	float2 uv: TEXTCOORD1;
};

Output main(Input input) {
	Output output;
	output.position = mul(mvp, float4(input.position, 1));
	output.color = input.color;
	output.uv = input.uv;

	return output;
}