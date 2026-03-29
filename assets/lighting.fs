#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec3 lightDir;
uniform vec3 lightColor;
uniform vec3 ambientColor;
uniform vec3 viewPos;

out vec4 finalColor;

void main() {
    vec4 texColor = texture(texture0, fragTexCoord);
    vec3 baseColor = texColor.rgb * colDiffuse.rgb;

    // Ambient
    vec3 ambient = ambientColor * baseColor;

    // Diffuse
    vec3 norm = normalize(fragNormal);
    float diff = max(dot(norm, -normalize(lightDir)), 0.0);
    vec3 diffuse = lightColor * diff * baseColor;

    // Specular
    vec3 viewDir = normalize(viewPos - fragPosition);
    vec3 reflectDir = reflect(normalize(lightDir), norm);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 16.0);
    vec3 specular = lightColor * spec * 0.3;

    vec3 result = ambient + diffuse + specular;
    finalColor = vec4(result, texColor.a * colDiffuse.a);
}
