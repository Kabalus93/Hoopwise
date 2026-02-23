import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface PhaseRequest {
  prompt: string;
  programContext?: string;
}

interface PhaseSuggestion {
  title: string;
  focus: string[];
  durationWeeks: number;
  description: string;
  objectives: string[];
  intensity: number;
  volume: number;
  suggestedSessions: SessionSuggestion[];
}

interface SessionSuggestion {
  title: string;
  sessionType: string;
  durationMinutes: number;
  focus: string;
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

    const { prompt, programContext }: PhaseRequest = await req.json();

    if (!prompt || prompt.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Prompt is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const contextInfo = programContext ? `\nProgram context: ${programContext}` : "";

    const systemPrompt = `You are a basketball coaching assistant. Generate a detailed training phase (micro-cycle) based on the user's description.

You MUST respond with ONLY valid JSON matching this exact structure (no markdown, no code blocks, no explanation - ONLY the JSON object):
{
  "title": "string - phase name like Foundation Phase, Skill Development, Competition Prep",
  "focus": ["string array - 2-4 training focus areas from: shooting, defense, offense, conditioning, skills, teamwork, footwork"],
  "durationWeeks": number - weeks for this phase (1-6),
  "description": "string - 2-3 sentence phase description",
  "objectives": ["string array - 3-5 specific objectives for this phase"],
  "intensity": number - training intensity 1-10,
  "volume": number - training volume 1-10,
  "suggestedSessions": [
    {
      "title": "string - session name",
      "sessionType": "string - one of: training, scrimmage, game, evaluation",
      "durationMinutes": number - 60-120,
      "focus": "string - main focus of this session"
    }
  ]
}

Include 3-6 suggested sessions that fit the phase focus.`;

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
          { role: "user", content: `${contextInfo}\n\nCreate a training phase based on this idea: ${prompt}` }
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
    const phase: PhaseSuggestion = JSON.parse(content);

    return new Response(JSON.stringify(phase), {
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
