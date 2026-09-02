#include <metal_stdlib>
#include "../BridgingHeader.h"
using namespace metal;

kernel void applyColliderMaterials(
    device GridCell* cells [[buffer(0)]],
    constant int* materialIndices [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) {
        return;
    }

    cells[id].materialIndex = materialIndices[id];
}
