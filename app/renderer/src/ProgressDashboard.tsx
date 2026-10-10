import { useEffect, useRef, useState } from 'react';
import { Award, Check, ChevronLeft, ChevronRight, Flame, Settings2, Target, Trophy } from 'lucide-react';
import { dateKey, emptyUsage, savedTimeLabel, shiftDay, usageSummary, type Usage } from '../../shared/usage';
import type { Command } from '../../shared/protocol';

const number = new Intl.NumberFormat();

export function UsageTotals({ usage = emptyUsage }: { usage: Usage | undefined }): React.JSX.Element {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 60_000);
    return () => window.clearInterval(timer);
  }, []);
  const summary = usageSummary(usage, now);
  return (
    <dl className="progress-totals">
      <div><dt>Words spoken</dt><dd>{number.format(summary.words)}</dd><span>All time</span></div>
      <div><dt>Typing time saved</dt><dd>{savedTimeLabel(summary.secondsSaved)}</dd><span>Estimated at {usage.typingWpm} words / min</span></div>
      <div><dt>Current streak <Flame size={15} aria-hidden="true" /></dt><dd>{summary.streak} <small>{summary.streak === 1 ? 'day' : 'days'}</small></dd><span>Best streak: {summary.bestStreak} {summary.bestStreak === 1 ? 'day' : 'days'}</span></div>
    </dl>
  );
}

export function ProgressDashboard({ usage: providedUsage, preview, run, pending }: {
  usage: Usage | undefined;
  preview: boolean;
  run: (command: Command) => Promise<void>;
  pending: boolean;
}): React.JSX.Element {
  const [now, setNow] = useState(() => new Date());
  const [yearOffset, setYearOffset] = useState(0);
  const gridRef = useRef<HTMLDivElement>(null);
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [previewPreferences, setPreviewPreferences] = useState<{ dailyGoal: number; typingWpm: number } | null>(null);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 60_000);
    return () => window.clearInterval(timer);
  }, []);
  const usage = previewPreferences ? { ...(providedUsage ?? emptyUsage), ...previewPreferences } : providedUsage ?? emptyUsage;
  const summary = usageSummary(usage, now);
  const today = dateKey(now);
  const todayWords = usage.days[today]?.words ?? 0;
  const goalComplete = todayWords >= usage.dailyGoal;
  const start = new Date(now.getFullYear() + yearOffset, now.getMonth() - 11, 1, 12);
  const end = new Date(now.getFullYear() + yearOffset, now.getMonth() + 1, 0, 12);
  const gridStart = shiftDay(start, -((start.getDay() + 6) % 7));
  const dates: Date[] = [];
  for (let cursor = gridStart; cursor <= end; cursor = shiftDay(cursor, 1)) dates.push(cursor);
  const columns = Math.ceil(dates.length / 7);
  const monthLabels = Array.from({ length: 12 }, (_, index) => {
    const date = new Date(start.getFullYear(), start.getMonth() + index, 1, 12);
    const dayIndex = dates.findIndex(day => dateKey(day) === dateKey(date));
    return { label: date.toLocaleDateString(undefined, { month: 'short' }), column: Math.floor(dayIndex / 7) + 1 };
  });
  const period = `${start.toLocaleDateString(undefined, { month: 'short', year: 'numeric' })} – ${end.toLocaleDateString(undefined, { month: 'short', year: 'numeric' })}`;
  const activeDays = dates.filter(date => date >= start && (usage.days[dateKey(date)]?.words ?? 0) > 0).length;
  const detailKey = selectedDay ?? (yearOffset === 0 ? today : dateKey(end));
  const detail = usage.days[detailKey];
  const badges = [
    { name: 'First words', hint: 'Complete your first dictation', unlocked: summary.sessions > 0, value: summary.sessions, target: 1, unit: 'dictations', icon: <MicBadge /> },
    { name: 'A thousand words', hint: 'Dictate 1,000 words', unlocked: summary.words >= 1000, value: summary.words, target: 1000, unit: 'words', icon: <Award size={21} /> },
    { name: 'On a roll', hint: 'Reach a 7-day streak', unlocked: summary.bestStreak >= 7, value: summary.bestStreak, target: 7, unit: 'days', icon: <Flame size={21} /> },
    { name: 'An hour back', hint: 'Save an estimated hour', unlocked: summary.secondsSaved >= 3600, value: Math.floor(summary.secondsSaved / 60), target: 60, unit: 'min saved', icon: <Trophy size={21} /> },
    { name: 'Voice regular', hint: 'Dictate 10,000 words', unlocked: summary.words >= 10000, value: summary.words, target: 10000, unit: 'words', icon: <Award size={21} /> },
  ];
  function setPreferences(dailyGoal: number, typingWpm: number): void {
    if (preview) setPreviewPreferences({ dailyGoal, typingWpm });
    else void run({ kind: 'setUsagePreferences', dailyGoal, typingWpm });
  }
  return <section className="progress-dashboard progress-expanded" aria-label="Your dictation progress">
    <div className="progress-heading"><h2 className="visually-hidden" id="activity-heading" tabIndex={-1}>Your activity</h2><span>{preview ? 'Sample progress · preview' : 'Only usage totals are saved on this Mac'}</span></div>
    <UsageTotals usage={usage} />
    <dl className="stats-session-totals">
      <div><dt>Completed dictations</dt><dd>{number.format(summary.sessions)}</dd></div>
      <div><dt>Active days, all time</dt><dd>{number.format(Object.values(usage.days).filter(day => day.words > 0).length)}</dd></div>
      <div><dt>Daily goals reached</dt><dd>{number.format(Object.values(usage.days).filter(day => day.words >= usage.dailyGoal).length)}</dd><span>At your current {number.format(usage.dailyGoal)} word goal</span></div>
    </dl>
    <section className="activity-calendar" aria-label="Yearly dictation activity">
      <div className="calendar-heading"><h3>Dictation activity</h3><div className="calendar-controls">
        <button type="button" aria-label="Previous year" onClick={() => { setYearOffset(value => value - 1); setSelectedDay(null); }}><ChevronLeft size={16} /></button>
        <span className="activity-period">{period}</span>
        <button type="button" aria-label="Next year" disabled={yearOffset === 0} onClick={() => { setYearOffset(value => value + 1); setSelectedDay(null); }}><ChevronRight size={16} /></button>
      </div></div>
      <div className="activity-scroll">
        <div className="activity-heatmap" style={{ gridTemplateColumns: `28px repeat(${columns}, minmax(0, 1fr))` }}>
          <div className="activity-weekdays" aria-hidden="true"><span>Mon</span><span>Wed</span><span>Fri</span></div>
          <div className="heatmap-grid" ref={gridRef}>
            {dates.map((date, index) => {
              const key = dateKey(date);
              const words = usage.days[key]?.words ?? 0;
              const level = words === 0 ? 0 : words >= usage.dailyGoal ? 4 : Math.max(1, Math.ceil(words / usage.dailyGoal * 3));
              const label = `${date.toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric' })}: ${number.format(words)} words${words >= usage.dailyGoal ? ', daily goal reached' : ''}`;
              return date < start ? <span className="heatmap-blank" key={key} /> : <button type="button" className="heatmap-day" key={key} data-level={level}
                aria-label={label} title={label} aria-current={key === today ? 'date' : undefined} aria-pressed={detailKey === key} disabled={key > today}
                tabIndex={detailKey === key ? 0 : -1} onClick={() => setSelectedDay(key)}
                onKeyDown={event => {
                  const offset = event.key === 'ArrowRight' ? 7 : event.key === 'ArrowLeft' ? -7 : event.key === 'ArrowDown' ? 1 : event.key === 'ArrowUp' ? -1 : 0;
                  if (!offset) return;
                  event.preventDefault();
                  const targetDate = dates[index + offset];
                  if (targetDate && targetDate >= start && dateKey(targetDate) <= today) {
                    setSelectedDay(dateKey(targetDate));
                    gridRef.current?.querySelector<HTMLButtonElement>(`button[data-date="${dateKey(targetDate)}"]`)?.focus();
                  }
                }} data-date={key} />;
            })}
          </div>
          <div className="heatmap-months">{monthLabels.map(month => <span key={month.column} style={{ gridColumn: month.column }}>{month.label}</span>)}</div>
        </div>
      </div>
      <div className="heatmap-footer">
        <p className="calendar-detail" aria-live="polite"><strong>{detailKey === today ? 'Today' : new Date(`${detailKey}T12:00:00`).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}</strong><span>{number.format(detail?.words ?? 0)} words · {detail?.sessions ?? 0} {(detail?.sessions ?? 0) === 1 ? 'dictation' : 'dictations'}</span></p>
        <div className="calendar-legend"><span>{activeDays} active {activeDays === 1 ? 'day' : 'days'}</span><span>Less</span><span className="heatmap-scale" aria-label="Activity intensity, less to more">{[0, 1, 2, 3, 4].map(level => <i key={level} data-level={level} />)}</span><span>More</span></div>
      </div>
    </section>
    <div className="progress-layout">
      <section className={`daily-goal${goalComplete ? ' is-complete' : ''}`} aria-labelledby="daily-goal-heading">
        <div className="goal-title"><Target size={19} aria-hidden="true" /><h3 id="daily-goal-heading">Daily goal</h3></div>
        <div className="goal-count"><strong>{number.format(todayWords)}</strong><span>/ {number.format(usage.dailyGoal)} words</span></div>
        <progress aria-label="Today's word goal" max={usage.dailyGoal} value={Math.min(todayWords, usage.dailyGoal)} />
        <p className="goal-message" role="status">{goalComplete ? <><Check size={16} aria-hidden="true" /> Daily goal reached.</> : todayWords > 0 ? `${number.format(usage.dailyGoal - todayWords)} more words to your daily goal.` : 'Your first dictation starts today\'s streak.'}</p>
        <details className="progress-preferences"><summary><Settings2 size={14} aria-hidden="true" /> Adjust your goal</summary>
          <p className="streak-note">Any completed dictation counts toward your streak.</p>
          <label>Daily word goal<select value={usage.dailyGoal} disabled={pending} onChange={event => setPreferences(Number(event.target.value), usage.typingWpm)}>
            {[100, 250, 500, 1000, 2000, 5000, 10000].map(goal => <option key={goal} value={goal}>{number.format(goal)} words</option>)}
          </select></label>
          <label>Estimated typing speed<select value={usage.typingWpm} disabled={pending} onChange={event => setPreferences(usage.dailyGoal, Number(event.target.value))}>
            {[10, 20, 30, 40, 50, 60, 80, 100, 150, 200].map(wpm => <option key={wpm} value={wpm}>{wpm} words / min</option>)}
          </select></label>
          <p>Time saved compares typing at this speed with your dictation and processing time. It is an estimate.</p>
          {preview && <p>Changes here affect this preview only.</p>}
        </details>
      </section>
    <section className="milestones" aria-labelledby="milestones-heading">
      <div className="milestones-heading"><h3 id="milestones-heading">Milestones</h3><span>{badges.filter(badge => badge.unlocked).length} / {badges.length} earned</span></div>
      <ul>{badges.map(badge => <li key={badge.name} className={badge.unlocked ? 'badge-earned' : ''}>
        <span className="milestone-icon" aria-hidden="true">{badge.icon}{badge.unlocked && <Check size={10} className="badge-check" />}</span>
        <span><strong>{badge.name}</strong><span>{badge.hint}</span><span className="milestone-progress"><progress aria-label={`${badge.name} progress`} value={Math.min(badge.value, badge.target)} max={badge.target} /><span>{badge.unlocked ? 'Earned' : `${number.format(badge.value)} / ${number.format(badge.target)} ${badge.unit}`}</span></span>
        <span className="visually-hidden">{badge.unlocked ? 'Earned' : 'Not yet earned'}</span></span>
      </li>)}</ul>
    </section>
    </div>
  </section>;
}

function MicBadge(): React.JSX.Element {
  return <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true"><path d="M5 9v6M10 5v14M15 7v10M20 10v4" /></svg>;
}
