import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface SessionRequest {
  prompt: string;
  phaseContext?: string;
}

interface SessionSuggestion {
  title: string;
  sessionType: string;
  durationMinutes: number;
  description: string;
  warmupDrills: DrillSuggestion[];
  mainDrills: DrillSuggestion[];
  cooldownDrills: DrillSuggestion[];
  coachNotes: string;
}

interface DrillSuggestion {
  name: string;
  durationMinutes: number;
  description: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
    if (!GROQ_API_KEY) {
      throw new Error("GROQ_API_KEY not configured");
    }

    const { prompt, phaseContext }: SessionRequest = await req.json();

    if (!prompt || prompt.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Prompt is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const contextInfo = phaseContext ? `\nPhase context: ${phaseContext}` : "";

    const systemPrompt = `You are a basketball coaching assistant. Generate a detailed training session plan based on the user's description.

You MUST respond with ONLY valid JSON matching this exact structure (no markdown, no code blocks, no explanation - ONLY the JSON object):
{
  "title": "string - session name like Shooting Fundamentals, Defensive Drills",
  "sessionType": "string - one of: training, scrimmage, game, evaluation",
  "durationMinutes": number - total session duration 60-120,
  "description": "string - 2-3 sentence session description",
  "warmupDrills": [
    {
      "name": "string - drill name",
      "durationMinutes": number - 5-10,
      "description": "string - brief drill description"
    }
  ],
  "mainDrills": [
    {
      "name": "string - drill name",
      "durationMinutes": number - 10-20,
      "description": "string - brief drill description"
    }
  ],
  "cooldownDrills": [
    {
      "name": "string - drill name",
      "durationMinutes": number - 5-10,
      "description": "string - brief drill description"
    }
  ],
  "coachNotes": "string - key coaching points and reminders for this session"
}

Include 2-3 warmup drills, 3-5 main drills, and 1-2 cooldown drills.`;

    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${GROQ_API_KEY}`,
      },
      body: JSON.stringify({
        model: "llama-3.3-70b-versatile",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: `${contextInfo}\n\nCreate a training session based on this idea: ${prompt}` }
        ],
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Groq API error:", errorText);
      throw new Error(`Groq error ${response.status}: ${errorText}`);
    }

    const data = await response.json();
    let content = data.choices?.[0]?.message?.content;

    if (!content) {
      throw new Error("No content in response");
    }

    content = content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    const session: SessionSuggestion = JSON.parse(content);

    return new Response(JSON.stringify(session), {
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
