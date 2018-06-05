cbuffer SceneBuffer: register(b0)
{
  row_major float4x4 worldViewProjection;
}

void main(
  float3 inputPosition: POSITION0,
  float4 inputColor: COLOR0,
  out float4 outPosition: SV_POSITION,
  out float4 outColor: COLOR0)
{
  outPosition = mul(float4(inputPosition, 1.0f), worldViewProjection);
  outColor = inputColor;
}