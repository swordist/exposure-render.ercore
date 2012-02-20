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

#include "Geometry.cuh"

#define KRNL_TONE_MAP_BLOCK_W		16 
#define KRNL_TONE_MAP_BLOCK_H		8
#define KRNL_TONE_MAP_BLOCK_SIZE	KRNL_TONE_MAP_BLOCK_W * KRNL_TONE_MAP_BLOCK_H

KERNEL void KrnlToneMap(FrameBuffer* pFrameBuffer)
{
	const int X 	= blockIdx.x * blockDim.x + threadIdx.x;
	const int Y		= blockIdx.y * blockDim.y + threadIdx.y;

	if (X >= pFrameBuffer->Resolution[0] || Y >= pFrameBuffer->Resolution[1])
		return;

	const ColorXYZAf Color = pFrameBuffer->CudaRunningEstimateXyza.Get(X, Y);

	ColorRGBf RgbHdr;

	RgbHdr.FromXYZ(Color.GetX(), Color.GetY(), Color.GetZ());

	RgbHdr.SetR(Clamp(1.0f - expf(-(RgbHdr.GetR() * gCamera.m_InvExposure)), 0.0, 1.0f));
	RgbHdr.SetG(Clamp(1.0f - expf(-(RgbHdr.GetG() * gCamera.m_InvExposure)), 0.0, 1.0f));
	RgbHdr.SetB(Clamp(1.0f - expf(-(RgbHdr.GetB() * gCamera.m_InvExposure)), 0.0, 1.0f));

	pFrameBuffer->CudaEstimateRgbaLdr.GetPtr(X, Y)->SetR((unsigned char)Clamp((255.0f * powf(RgbHdr.GetR(), gCamera.m_InvGamma)), 0.0f, 255.0f));
	pFrameBuffer->CudaEstimateRgbaLdr.GetPtr(X, Y)->SetG((unsigned char)Clamp((255.0f * powf(RgbHdr.GetG(), gCamera.m_InvGamma)), 0.0f, 255.0f));
	pFrameBuffer->CudaEstimateRgbaLdr.GetPtr(X, Y)->SetB((unsigned char)Clamp((255.0f * powf(RgbHdr.GetB(), gCamera.m_InvGamma)), 0.0f, 255.0f));
	pFrameBuffer->CudaEstimateRgbaLdr.GetPtr(X, Y)->SetA(0);
}

void ToneMap(FrameBuffer* pFrameBuffer, int Width, int Height)
{
	const dim3 BlockDim(KRNL_TONE_MAP_BLOCK_W, KRNL_TONE_MAP_BLOCK_H);
	const dim3 GridDim((int)ceilf((float)Width / (float)BlockDim.x), (int)ceilf((float)Height / (float)BlockDim.y));

	KrnlToneMap<<<GridDim, BlockDim>>>(pFrameBuffer);
	cudaThreadSynchronize();
	HandleCudaKernelError(cudaGetLastError(), "Tone Map");
}