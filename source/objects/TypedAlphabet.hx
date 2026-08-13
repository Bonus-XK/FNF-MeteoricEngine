package objects;

class TypedAlphabet extends MenuText
{
	public var onFinish:Void->Void = null;
	public var finishedText:Bool = false;
	public var delay:Float = 0.05;
	public var sound:String = 'dialogue';
	public var volume:Float = 1;

	private var _fullText:String = '';
	private var _curLetter:Int = -1;
	private var _timeToUpdate:Float = 0;

	public function new(x:Float, y:Float, text:String = "", ?delay:Float = 0.05, ?bold:Bool = false)
	{
		super(x, y, text, bold);

		this.delay = delay;
		_fullText = text == null ? '' : text;
		resetDialogue();
	}

	public var rows(get, never):Int;
	function get_rows():Int
	{
		return text.split('\n').length;
	}

	public function startText(newText:String)
	{
		_fullText = newText == null ? '' : newText;
		resetDialogue();
	}

	override function update(elapsed:Float)
	{
		if(!finishedText && _fullText.length > 0)
		{
			_timeToUpdate += elapsed;
			var playedSound:Bool = false;
			while(_timeToUpdate >= delay)
			{
				_curLetter++;
				text = _fullText.substr(0, _curLetter + 1);
				if(!playedSound && sound != '' && (delay > 0.025 || _curLetter % 2 == 0))
				{
					FlxG.sound.play(Paths.sound(sound), volume);
				}
				playedSound = true;

				if(_curLetter >= _fullText.length - 1)
				{
					finishedText = true;
					if(onFinish != null) onFinish();
					_timeToUpdate = 0;
					break;
				}
				_timeToUpdate = 0;
			}
		}

		super.update(elapsed);
	}

	public function finishText()
	{
		if(finishedText) return;

		text = _fullText;
		if(sound != '') FlxG.sound.play(Paths.sound(sound), volume);
		finishedText = true;

		if(onFinish != null) onFinish();
		_timeToUpdate = 0;
	}

	public function resetDialogue()
	{
		_curLetter = -1;
		finishedText = false;
		_timeToUpdate = 0;
		text = '';
	}
}
