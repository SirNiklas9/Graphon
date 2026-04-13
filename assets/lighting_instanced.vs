#version 330

// Standard vertex attributes (Raylib default locations 0-5)
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;
in vec4 vertexTangent;

// Instance model matrix — 4 vec4 columns at locations 6-9
// Raylib's DrawMeshInstanced uploads these via vertex attribute divisor
layout(location = 6) in mat4 matModel;

// View and projection uploaded as uniforms by DrawMeshInstanced
uniform mat4 matView;
uniform mat4 matProjection;

out vec3 fragPosition;
out vec2 fragTexCoord;
out vec3 fragNormal;
out vec4 fragColor;
out mat3 fragTBN;

void main() {
    fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));
    fragTexCoord = vertexTexCoord;

    // Normal matrix from model matrix
    mat3 normalMat = transpose(inverse(mat3(matModel)));
    fragNormal = normalize(normalMat * vertexNormal);
    fragColor = vertexColor;

    // TBN matrix for normal mapping
    vec3 T = normalize(vec3(matModel * vec4(vertexTangent.xyz, 0.0)));
    vec3 N = fragNormal;
    T = normalize(T - dot(T, N) * N);
    vec3 B = cross(N, T) * vertexTangent.w;
    fragTBN = mat3(T, B, N);

    // MVP computed per-instance (can't use precomputed mvp uniform)
    gl_Position = matProjection * matView * matModel * vec4(vertexPosition, 1.0);
}
