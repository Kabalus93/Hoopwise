import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface SessionData {
  title: string;
  sessionType: string;
  durationMinutes: number;
  description: string;
  dayOfWeek: string;
  weekNumber: number;
  objectives: string[];
  warmupDrills: string[];
  mainDrills: string[];
  cooldownActivities: string[];
}

interface PhaseData {
  title: string;
  focus: string[];
  durationWeeks: number;
  description: string;
  objectives: string[];
  sessions: SessionData[];
}

interface ProgramPhasesResponse {
  phases: PhaseData[];
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { prompt, ageGroup, skillLevel, durationWeeks } = await req.json();

    const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
    if (!GROQ_API_KEY) {
      throw new Error("GROQ_API_KEY not configured");
    }

    const systemPrompt = `You are an expert European youth basketball coach and training program designer with deep knowledge of:
- FIBA Europe youth development guidelines
- Age-appropriate skill progressions for youth players
- Periodization and training phase planning
- Modern basketball coaching methodologies

Your task is to generate detailed, practical training phases and sessions that follow European basketball federation standards.

IMPORTANT GUIDELINES FOR EACH AGE GROUP:

U8 (Mini Basketball):
- Focus: Fun, basic motor skills, ball familiarity
- Court: Mini court, lower basket (2.6m)
- Ball: Size 5
- Sessions: 45-60 min max
- Key skills: Dribbling with both hands, basic catches, stationary shooting form

U10:
- Focus: Fundamental movement, basic basketball skills
- Court: Mini court transitioning to half court
- Ball: Size 5
- Sessions: 60 min
- Key skills: Layups, passing (chest, bounce), defensive stance

U12:
- Focus: Individual skill development, 1v1, 2v2
- Court: Full court introduction
- Ball: Size 5-6
- Sessions: 60-75 min
- Key skills: Jump stops, pivoting, shooting form, help defense concepts

U14:
- Focus: Position-less basketball, team concepts
- Court: Full court
- Ball: Size 6-7
- Sessions: 75-90 min
- Key skills: Pick and roll basics, zone defense, free throw routine

U16:
- Focus: Position specialization begins, advanced tactics
- Court: Full court
- Ball: Size 7
- Sessions: 90 min
- Key skills: Advanced footwork, reading defenses, transition play

U18/Senior:
- Focus: Game preparation, tactical mastery
- Court: Full court
- Ball: Size 7
- Sessions: 90-120 min
- Key skills: Game film analysis, situational plays, mental preparation

SESSION STRUCTURE (酷讯 Unified Session Structure - every session, every age group, 90 minutes as three equal blocks; scale all three blocks equally for shorter sessions):
1. Warm-up (30 min): the SAME routine every session so it becomes second nature - Full Court Dribble Progression (regular, skip, in-and-out, alternate dribble), Layup Progression (no-dribble extended-hand run, ball around the waist, dribble basket to basket, with obstacles), Shooting Routine Ladder. Time left over goes to one small competitive game (Pass and Tag, Police and Thieves, Ten Passes, Dribble Knockout, Sharks and Minnows Dribble, Relay Dribble Races). Put the routine drills and the game in warmupDrills.
2. Skills (30 min): first review the previous session's skill (Skill Review Challenge), then introduce the next skill on the age-group roadmap only if the group is ready, then compete with it (1v1 from Triple Threat, Give and Go live, etc.). Put these in mainDrills. Progress one or two skills per session, in roadmap order.
3. Game (30 min): a regular basketball game (3v3 for U6-U8, 3v3/4v4 for U10, 4v4/5v5 for U12+) with one or two coach constraints tied to the session's skill: 3-second individual possession, minimum passes before a shot, no dribble, layups only, weak hand only, skill bonus point. Put the game and its constraint in cooldownActivities (that field is the Game block).
Never add a separate cool-down block; the session ends with the game.

Always include:
- Specific drill names and descriptions
- Time allocations
- Progressions within and between sessions
- Age-appropriate language and expectations`;

    const userPrompt = `${prompt}

Generate a structured JSON response with training phases for a ${durationWeeks}-week program.

Return ONLY valid JSON in this exact format:
{
  "phases": [
    {
      "title": "Phase name (e.g., Foundation, Development, Competition)",
      "focus": ["skill1", "skill2"],
      "durationWeeks": number,
      "description": "Detailed phase description",
      "objectives": ["objective1", "objective2", "objective3"],
      "sessions": [
        {
          "title": "Session title",
          "sessionType": "practice",
          "durationMinutes": 60,
          "description": "Session overview",
          "dayOfWeek": "monday",
          "weekNumber": 1,
          "objectives": ["session objective 1", "session objective 2"],
          "warmupDrills": ["drill1", "drill2"],
          "mainDrills": ["drill1 with description", "drill2 with description"],
          "cooldownActivities": ["activity1", "activity2"]
        }
      ]
    }
  ]
}

Focus areas should use lowercase single words like: shooting, passing, dribbling, defense, rebounding, conditioning, fundamentals, teamwork, positioning, footwork

Create ${Math.ceil(durationWeeks / 6)} to ${Math.ceil(durationWeeks / 4)} phases with appropriate sessions for each phase.
Each phase should have 2-4 sessions per week of training.
Make drill descriptions specific and actionable.`;

    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${GROQ_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "llama-3.3-70b-versatile",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.7,
        max_tokens: 8000,
        response_format: { type: "json_object" },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Groq API error:", errorText);
      throw new Error(`Groq API error: ${response.status}`);
    }

    const data = await response.json();
    const content = data.choices[0]?.message?.content;

    if (!content) {
      throw new Error("No content in response");
    }

    let parsedResponse: ProgramPhasesResponse;
    try {
      parsedResponse = JSON.parse(content);
    } catch (parseError) {
      console.error("Failed to parse response:", content);
      throw new Error("Invalid JSON response from AI");
    }

    // Validate response structure
    if (!parsedResponse.phases || !Array.isArray(parsedResponse.phases)) {
      throw new Error("Invalid response structure: missing phases array");
    }

    // Ensure each phase has required fields
    for (const phase of parsedResponse.phases) {
      if (!phase.title || !phase.sessions) {
        throw new Error("Invalid phase structure");
      }
      // Ensure focus is an array
      if (!Array.isArray(phase.focus)) {
        phase.focus = ["fundamentals"];
      }
      // Ensure sessions have required fields
      for (const session of phase.sessions) {
        if (!session.title) {
          session.title = "Training Session";
        }
        if (!session.sessionType) {
          session.sessionType = "practice";
        }
        if (!session.durationMinutes) {
          session.durationMinutes = 60;
        }
      }
    }

    return new Response(JSON.stringify(parsedResponse), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Failed to generate program phases" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
