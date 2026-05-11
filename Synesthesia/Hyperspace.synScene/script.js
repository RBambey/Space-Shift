let lastTextureStyle = 0.0;

function update(dt) {
    if (texture_style !== lastTextureStyle) {
        lastTextureStyle = texture_style;
        setControl("travel_speed", 0.5);
    }
}
