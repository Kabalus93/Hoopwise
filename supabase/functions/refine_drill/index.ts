import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface DrillRequest {
  prompt: string;
}

interface DrillSuggestion {
  name: string;
  category: string;
  difficulty: string;
  duration: number;
  description: string;
  instructions: string[];
  keyPoints: string[];
  equipment: string[];
  tags: string[];
  minPlayers: number;
  maxPlayers: number | null;
  variations: string[];
  videoUrl: string | null;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
    if (!GEMINI_API_KEY) {
      throw new Error("GEMINI_API_KEY not configured");
    }

    const { prompt }: DrillRequest = await req.json();

    if (!prompt || prompt.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Prompt is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const systemPrompt = `You are a basketball coaching assistant. Generate a detailed basketball drill based on the user's description.

You MUST respond with ONLY valid JSON matching this exact structure (no markdown, no code blocks, no explanation - ONLY the JSON object):
{
  "name": "string - creative drill name",
  "category": "string - one of: shooting, dribbling, passing, defense, conditioning, teamwork, footwork",
  "difficulty": "string - one of: beginner, intermediate, advanced",
  "duration": number - minutes (5-30),
  "description": "string - 2-3 sentence description",
  "instructions": ["string array - step by step instructions, 4-8 steps"],
  "keyPoints": ["string array - 3-5 coaching points to emphasize"],
  "equipment": ["string array - required equipment like basketballs, cones, etc"],
  "tags": ["string array - 3-6 relevant tags"],
  "minPlayers": number - minimum players needed (1-15),
  "maxPlayers": number or null - maximum players or null if unlimited,
  "variations": ["string array - 2-3 ways to modify the drill"],
  "videoUrl": null
}`;

    const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=${GEMINI_API_KEY}`;
    
    const response = await fetch(geminiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                text: `${systemPrompt}\n\nCreate a basketball drill based on this idea: ${prompt}`,
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 1024,
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Gemini API error:", errorText);
      throw new Error(`Gemini error ${response.status}: ${errorText}`);
    }

    const data = await response.json();
    let content = data.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!content) {
      throw new Error("No content in response");
    }

    // Clean up the response - remove markdown code blocks if present
    content = content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();

    // Parse the JSON response from Gemini
    const drill: DrillSuggestion = JSON.parse(content);

    return new Response(JSON.stringify(drill), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error.message);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
