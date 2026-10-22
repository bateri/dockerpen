// Written by tools/icon.mjs; change the shapes there and run it again.

import type { Icon } from "@modelcontextprotocol/server";

/**
 * dockerpen's icon, the mark its view shows, for a dark ground and a light one (MCP's `theme`),
 * 32 and 64 pixels a side, as PNGs in `data:` URIs: a terminal draws an icon only from the
 * bytes it is given, and never fetches one.
 */
export const ICONS: Icon[] = [
  {
    src: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAABGElEQVR42u2WPQrCQBBGYyNCKgvFgCBCwCq9V0iVJkWEFBaWU3iEnCDXyPSWKTxCjpJq6phiVlQUd93d/IDF6zLzPbLMMA4gOX0i++EKkFJAOkqSco0RgT0g1YDUKFJzrbZA9UO4oDIh0GgyfoFaI7w2IZBpCGSmxhAAqQSkqyQl1xjbA70soh0gnQDprMmJeykJhIB0MUwoKzBrjQsLAgX3/irgWwgX+DICgUWBYBQCnkUBT3YKcgvhucoYrg1L5NxTeRN6/G46eCqbcAJIc0BaWmLOGW8FFu0FEwHSwTIRZz0JTAEp7iBcEHPmXWDTYbhg8yiw7UFg+xcYlIALSEmH4QlnOq93QNJRuP9pE7r8a2ziDuoqvgF7ZHFGIfNuBQAAAABJRU5ErkJggg==",
    mimeType: "image/png",
    sizes: ["32x32"],
    theme: "dark",
  },
  {
    src: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAB4UlEQVR42u3bsWoCQRAGYAs58ghBBA0cXJU2CCInXGkror3lFBbp8hSSSixS3pRCHsDC0sKHkaksDAdzEORyxmTXnb2b4i918396YWdIGoDUqHMaCqAARt9wDEgpIG0tJeUzxAE8AtIOkM53yo7PFAHwAEiHO5bPc+CznQMsHJTPs5AAsHcIsJcAcHIIcJIAcHYcBVAAxwBHh+WPEgC2DgG2EgCmDgGmUq7CqYPyqaRZoAlI73e6E5z4rKbEabALSK+AtAakD8NZ83t3dR+gADIAslG0A0jPjtP5z1j8lxdlB74B0gaQPoVkwz9TxzZAX1jxIoi+LYBIePnvCJENgKUH5fMsTQO0PSqfp20SYOghwNAkQOIhQKIACqAACqAAhgBCDwFC0zfBlUflVzauwgOPAAa2psG5B+XntvcBA6GPw+qWT97ERijk37QSEupOUAHsAAQ8Vz95mjZ3uBkge9ELIE0AaeZ5Jtwl+C1AtmIeVaD4ZUZF6/Of7v2ziia5BtCqcPk8rTKAXg0AemUASQ0AEgVQAAVQAAVQAAUoBIhrABCXAUQ1AIjKAAL+r6yqlh9fjsVF02CL/wa3auWnl4NQ2UKkVbFvwrio/LWVWMDPSyxo+3trYu4Q6FJUARSgMF+OmMIYOYsOngAAAABJRU5ErkJggg==",
    mimeType: "image/png",
    sizes: ["64x64"],
    theme: "dark",
  },
  {
    src: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAABF0lEQVR42u2WMQrCQBBFYyNCKgvFgPARAlbpvUIqG4sIwliktPAIniDX8ACWKaynylFyhGgxERXFXXc3iWDxusz8R5YZxgOx1yaqH05AvAHxVpGN1FgRWIC4BHGlSSm1xgLFF+E1hQ2BypDfFygNwksbAgcDgYOtMdyBOAfxWZFcaqztgVYW0RzEKYj3hqTSS0sgBvHJMrGqwOBqfHQgcJTeHwVCB+E1oYpA5FAg+gmBwKFAoDoFmYPwTGcMp5YlMumpvQkDeTcTAp1N2APxEMRjRwwl46XA6HrBLEG8dsxSsh4E+iBeNRBes5LMmwAaDK/BvcCsBYHZX6BTAj6IkwbDE8n0nu+ApKHw8N0m9OXXuMTv1FV8AYSYaRmTl4wKAAAAAElFTkSuQmCC",
    mimeType: "image/png",
    sizes: ["32x32"],
    theme: "light",
  },
  {
    src: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAB4UlEQVR42u3bsWoCQRAGYAs58gjhEMbAwVVpgyBywpW2IlpN4wNYpMtTSCqxSHmtkAewsBosfBhLC8PBHAS5nDHZdWfvpvhL3fyfXtgZkhYgtZqclgIogNE3HANSBkhbS8n4DHEAj4C0A6TznbLjM0UAPADS4Y7lixz4bOcACwfliywkAOwdAuwlAJwcApwkAJwdRwEUwDHA0WH5owSArUOArQSAqUOAqZSrcOagfCZpFmgD0vud7gQnPqstcRrsAtIrIK0B6cNw1vzeXd0HKIAMgHwUBUB6dhz4z1j8lxflB74B0gaQPoVkwz8T2AboCyteBtG3BRALL/8dIbYBsPSgfJGlaYCOR+WLdEwCDD0EGJoESD0ESBVAARRAARTAEEDkIUBk+ia48qj8ysZVeOARwMDWNDj3oPzc9j5gIPRxWN3yyZvYCEX8m1ZCIt0JKoAdgIDn6idP0+EONwPkL3oBpAkgzTzPhLsEvwXIV8yjGhS/zKhsff7TvX9W06TXAMIaly8SVgH0GgDQqwJIGwCQKoACKIACKIACKEApQNIAgKQKIG4AQFwFEPB/ZdW1/PhyLC6bBkP+G9y6lZ9eDkJVC5GwZt+EcVn5ayuxgJ+XRND299Yk3CHQpagCKEBpvgCaC6FkyovzBgAAAABJRU5ErkJggg==",
    mimeType: "image/png",
    sizes: ["64x64"],
    theme: "light",
  },
];
