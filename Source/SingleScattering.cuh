/*
	Copyright (c) 2011, T. Kroes <t.kroes@tudelft.nl>
	All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

	- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
	- Neither the name of the TU Delft nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#pragma once

#include "Transport.cuh"

DEV RaySample SampleRay(CRay R, CRNG& RNG)
{
	RaySample RS[3] = { RaySample(RaySample::Volume), RaySample(RaySample::Light), RaySample(RaySample::Reflector) };

	SampleVolume(R, RNG, RS[0]);
	SampleLights(R, RS[1], true);
	SampleReflectors(R, RS[2]);

	float T = FLT_MAX;

	RaySample NearestRS(RaySample::Volume);

	for (int i = 0; i < 3; i++)
	{
		if (RS[i].Valid && RS[i].T < T)
		{
			NearestRS = RS[i];
			T = RS[i].T;
		}
	}

	return NearestRS;
}

KERNEL void KrnlSingleScattering(FrameBuffer* pFrameBuffer)
{
	const int X		= blockIdx.x * blockDim.x + threadIdx.x;
	const int Y		= blockIdx.y * blockDim.y + threadIdx.y;

	if (X >= pFrameBuffer->m_Resolution[0] || Y >= pFrameBuffer->m_Resolution[1])
		return;
	
	CRNG RNG(pFrameBuffer->m_RandomSeeds1.GetPtr(X, Y), pFrameBuffer->m_RandomSeeds2.GetPtr(X, Y));

	Vec2f ScreenPoint;

	ScreenPoint.x = gCamera.m_Screen[0][0] + (gCamera.m_InvScreen[0] * (float)X);
	ScreenPoint.y = gCamera.m_Screen[1][0] + (gCamera.m_InvScreen[1] * (float)Y);
	
	CRay Re;

	Re.m_O		= ToVec3f(gCamera.m_Pos);
	Re.m_D		= Normalize(ToVec3f(gCamera.m_N) + (ScreenPoint.x * ToVec3f(gCamera.m_U)) - (ScreenPoint.y * ToVec3f(gCamera.m_V)));
	Re.m_MinT	= gCamera.m_ClipNear;
	Re.m_MaxT	= gCamera.m_ClipFar;

	if (gCamera.m_ApertureSize != 0.0f)
	{
		const Vec2f LensUV = gCamera.m_ApertureSize * ConcentricSampleDisk(RNG.Get2());

		const Vec3f LI = ToVec3f(gCamera.m_U) * LensUV.x + ToVec3f(gCamera.m_V) * LensUV.y;

		Re.m_O += LI;
		Re.m_D = Normalize(Re.m_D * gCamera.m_FocalDistance - LI);
	}

	ColorXYZf Lv = SPEC_BLACK, Li = SPEC_BLACK;

	const RaySample NearestRS = SampleRay(Re, RNG);
	
	if (NearestRS.Valid)
	{
		switch (NearestRS.Type)
		{
			case RaySample::Volume:
			{
				Lv += UniformSampleOneLightVolume(NearestRS, RNG);
				break;
			}
			
			case RaySample::Light:
			{
				Lv += NearestRS.Le;
				break;
			}

			case RaySample::Reflector:
			{
				Lv += UniformSampleOneLightReflector(NearestRS, RNG);

				CVolumeShader Shader(CVolumeShader::Brdf, NearestRS.N, NearestRS.Wo, ColorXYZf(gReflections.m_ReflectionObjects[NearestRS.ReflectorID].DiffuseColor), ColorXYZf(gReflections.m_ReflectionObjects[NearestRS.ReflectorID].SpecularColor), gReflections.m_ReflectionObjects[NearestRS.ReflectorID].Ior, gReflections.m_ReflectionObjects[NearestRS.ReflectorID].Glossiness);
				
				BrdfSample S;

				S.LargeStep(RNG);
				
				Vec3f Wi;

				float Pdf;

				const ColorXYZf F = Shader.SampleF(-Re.m_D, Wi, Pdf, S);

				const RaySample ReflectorRS = SampleRay(CRay(NearestRS.P, Wi, 0.0f), RNG);

				if (ReflectorRS.Valid && ReflectorRS.Type == RaySample::Volume)
				{
					Lv += F * UniformSampleOneLightVolume(ReflectorRS, RNG) / Pdf;
				}
				
				break;
			}
		}
	}

	ColorXYZAf L(Lv.GetX(), Lv.GetY(), Lv.GetZ(), 0.0f);

	pFrameBuffer->m_FrameEstimateXyza.Set(L, X, Y);
}

void SingleScattering(FrameBuffer* pFrameBuffer, int Width, int Height)
{
	const dim3 BlockDim(KRNL_SINGLE_SCATTERING_BLOCK_W, KRNL_SINGLE_SCATTERING_BLOCK_H);
	const dim3 GridDim((int)ceilf((float)Width / (float)BlockDim.x), (int)ceilf((float)Height / (float)BlockDim.y));

	KrnlSingleScattering<<<GridDim, BlockDim>>>(pFrameBuffer);
	cudaThreadSynchronize();
	HandleCudaKernelError(cudaGetLastError(), "Single Scattering");
}