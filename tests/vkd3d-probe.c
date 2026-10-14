/* Real GPU work through Wine's built-in vkd3d: clear a texture, copy and read back pixels. */
#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#include <initguid.h>
#include <windows.h>
#include <d3d12.h>
#include <stdio.h>
#define CHECK(call) do { HRESULT value=(call); if(FAILED(value)) { printf("FAIL %s 0x%08lx\n",#call,value); return 1; } } while(0)
int main(void) {
    ID3D12Device *device=NULL; ID3D12CommandQueue *queue=NULL; ID3D12CommandAllocator *allocator=NULL;
    ID3D12GraphicsCommandList *list=NULL; ID3D12Resource *texture=NULL,*readback=NULL; ID3D12DescriptorHeap *heap=NULL; ID3D12Fence *fence=NULL;
    CHECK(D3D12CreateDevice(NULL,D3D_FEATURE_LEVEL_11_0,&IID_ID3D12Device,(void**)&device));
    D3D12_COMMAND_QUEUE_DESC queueDesc={0};queueDesc.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;
    CHECK(ID3D12Device_CreateCommandQueue(device,&queueDesc,&IID_ID3D12CommandQueue,(void**)&queue));
    CHECK(ID3D12Device_CreateCommandAllocator(device,D3D12_COMMAND_LIST_TYPE_DIRECT,&IID_ID3D12CommandAllocator,(void**)&allocator));
    CHECK(ID3D12Device_CreateCommandList(device,0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator,NULL,&IID_ID3D12GraphicsCommandList,(void**)&list));
    D3D12_HEAP_PROPERTIES properties={0};properties.Type=D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC description={0};description.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;description.Width=16;description.Height=16;description.DepthOrArraySize=1;description.MipLevels=1;description.Format=DXGI_FORMAT_R8G8B8A8_UNORM;description.SampleDesc.Count=1;description.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    CHECK(ID3D12Device_CreateCommittedResource(device,&properties,D3D12_HEAP_FLAG_NONE,&description,D3D12_RESOURCE_STATE_RENDER_TARGET,NULL,&IID_ID3D12Resource,(void**)&texture));
    D3D12_DESCRIPTOR_HEAP_DESC heapDesc={0};heapDesc.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV;heapDesc.NumDescriptors=1;
    CHECK(ID3D12Device_CreateDescriptorHeap(device,&heapDesc,&IID_ID3D12DescriptorHeap,(void**)&heap));
    D3D12_CPU_DESCRIPTOR_HANDLE handle=ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(heap);
    ID3D12Device_CreateRenderTargetView(device,texture,NULL,handle);
    FLOAT colour[4]={0.25f,0.5f,0.75f,1.0f};ID3D12GraphicsCommandList_ClearRenderTargetView(list,handle,colour,0,NULL);
    D3D12_RESOURCE_BARRIER barrier={0};barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;barrier.Transition.pResource=texture;barrier.Transition.StateBefore=D3D12_RESOURCE_STATE_RENDER_TARGET;barrier.Transition.StateAfter=D3D12_RESOURCE_STATE_COPY_SOURCE;barrier.Transition.Subresource=D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    ID3D12GraphicsCommandList_ResourceBarrier(list,1,&barrier);
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint;UINT64 bytes=0;
    ID3D12Device_GetCopyableFootprints(device,&description,0,1,0,&footprint,NULL,NULL,&bytes);
    properties.Type=D3D12_HEAP_TYPE_READBACK;
    D3D12_RESOURCE_DESC buffer={0};buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;buffer.Width=bytes;buffer.Height=1;buffer.DepthOrArraySize=1;buffer.MipLevels=1;buffer.SampleDesc.Count=1;buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    CHECK(ID3D12Device_CreateCommittedResource(device,&properties,D3D12_HEAP_FLAG_NONE,&buffer,D3D12_RESOURCE_STATE_COPY_DEST,NULL,&IID_ID3D12Resource,(void**)&readback));
    D3D12_TEXTURE_COPY_LOCATION to={0},from={0};to.pResource=readback;to.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;to.PlacedFootprint=footprint;from.pResource=texture;from.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    ID3D12GraphicsCommandList_CopyTextureRegion(list,&to,0,0,0,&from,NULL);
    CHECK(ID3D12GraphicsCommandList_Close(list));ID3D12CommandList *commands[1]={(ID3D12CommandList*)list};ID3D12CommandQueue_ExecuteCommandLists(queue,1,commands);
    CHECK(ID3D12Device_CreateFence(device,0,D3D12_FENCE_FLAG_NONE,&IID_ID3D12Fence,(void**)&fence));CHECK(ID3D12CommandQueue_Signal(queue,fence,1));
    HANDLE event=CreateEventW(NULL,FALSE,FALSE,NULL);if(!event)return 2;CHECK(ID3D12Fence_SetEventOnCompletion(fence,1,event));
    if(WaitForSingleObject(event,15000)!=WAIT_OBJECT_0){puts("FAIL GPU fence timeout");return 3;}
    BYTE *pixels=NULL;D3D12_RANGE range={0,(SIZE_T)bytes};CHECK(ID3D12Resource_Map(readback,0,&range,(void**)&pixels));
    for(UINT y=0;y<16;y++)for(UINT x=0;x<16;x++){BYTE *p=pixels+footprint.Offset+y*footprint.Footprint.RowPitch+x*4;if(p[0]<63||p[0]>65||p[1]<127||p[1]>129||p[2]<190||p[2]>192||p[3]!=255){printf("FAIL pixel %u,%u: %u,%u,%u,%u\n",x,y,p[0],p[1],p[2],p[3]);return 4;}}
    D3D12_RANGE empty={0,0};ID3D12Resource_Unmap(readback,0,&empty);CloseHandle(event);
    ID3D12Fence_Release(fence);ID3D12DescriptorHeap_Release(heap);ID3D12Resource_Release(readback);ID3D12Resource_Release(texture);ID3D12GraphicsCommandList_Release(list);ID3D12CommandAllocator_Release(allocator);ID3D12CommandQueue_Release(queue);ID3D12Device_Release(device);
    puts("PASS: vkd3d DX12 GPU clear/copy/fence/readback, 256 pixels validated");return 0;
}
