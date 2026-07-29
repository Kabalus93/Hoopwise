import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ProgramRequest {
  prompt: string;
}

interface ProgramSuggestion {
  name: string;
  ageGroup: string;
  durationWeeks: number;
  description: string;
  objectives: string[];
  mascot: string;
  colorHex: string;
  phases: PhaseSuggestion[];
}

interface SessionSuggestion {
  title: string;
  sessionType: string;
  durationMinutes: number;
  description: string;
  dayOfWeek: string;
  weekNumber: number;
}

interface PhaseSuggestion {
  phaseNumber: number;
  title: string;
  focus: string[];
  durationWeeks: number;
  description: string;
  objectives: string[];
  sessions: SessionSuggestion[];
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

    const { prompt }: ProgramRequest = await req.json();

    if (!prompt || prompt.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Prompt is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const systemPrompt = `You are a basketball coaching assistant. Generate a detailed training program based on the user's description.

You MUST respond with ONLY valid JSON matching this exact structure (no markdown, no code blocks, no explanation - ONLY the JSON object):
{
  "name": "string - creative program name",
  "ageGroup": "string - one of: u8, u10, u12, u14, u16, u18, adult",
  "durationWeeks": number - total weeks (4-16),
  "description": "string - 2-3 sentence program description",
  "objectives": ["string array - 3-5 main program objectives"],
  "mascot": "string - one of: tiger, eagle, dragon, lion, wolf, bear, shark, phoenix",
  "colorHex": "string - hex color like #FF6B6B",
  "phases": [
    {
      "phaseNumber": number - phase order (1, 2, 3...),
      "title": "string - phase name like Foundation, Development, Competition",
      "focus": ["string array - training focus areas using these exact values: shooting, ballHandling, passing, defense, conditioning, teamPlay, gamePrep, recovery"],
      "durationWeeks": number - weeks for this phase,
      "description": "string - phase description",
      "objectives": ["string array - 2-4 phase-specific objectives"],
      "sessions": [
        {
          "title": "string - session title like Shooting Fundamentals Week 1",
          "sessionType": "string - one of: training, scrimmage, gamePrep, recovery",
          "durationMinutes": number - session duration (60-120),
          "description": "string - brief session description",
          "dayOfWeek": "string - one of: monday, tuesday, wednesday, thursday, friday, saturday, sunday",
          "weekNumber": number - which week of the phase (1, 2, 3...)
        }
      ]
    }
  ]
}

Include 2-4 phases that logically progress through the program duration. 

IMPORTANT for sessions:
- If the user specifies a training frequency (e.g., "once per week", "twice weekly"), create that many sessions per week for each phase
- If the user specifies a day of the week (e.g., "Saturdays", "Monday and Wednesday"), use those days
- Default to once per week on Saturday if not specified
- weekNumber should increment (1, 2, 3...) based on the phase duration - if a phase is 4 weeks, create sessions for weeks 1-4
- Each phase should have sessions covering its full duration based on the frequency`;

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
          { role: "user", content: `Create a basketball training program based on this idea: ${prompt}` }
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
    const program: ProgramSuggestion = JSON.parse(content);

    return new Response(JSON.stringify(program), {
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
